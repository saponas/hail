import traceback
import os
import base64
import concurrent
import logging
import uvloop
import asyncio
from aiohttp import web
import kubernetes_asyncio as kube
from py4j.java_gateway import JavaGateway, GatewayParameters, launch_gateway
from hailtop.utils import blocking_to_async, retry_transient_errors, find_spark_home
from hailtop.config import get_deploy_config
from hailtop.tls import internal_server_ssl_context
from hailtop.hail_logging import AccessLogger
from hailtop import version
from gear import setup_aiohttp_session, rest_authenticated_users_only, rest_authenticated_developers_only

uvloop.install()

DEFAULT_NAMESPACE = os.environ['HAIL_DEFAULT_NAMESPACE']
log = logging.getLogger('batch')
routes = web.RouteTableDef()


def java_to_web_response(jresp):
    status = jresp.status()
    value = jresp.value()
    log.info(f'response status {status} value {value}')
    if status in (400, 500):
        return web.Response(status=status, text=value)
    assert status == 200, status
    return web.json_response(status=status, text=value)


async def send_ws_response(thread_pool, endpoint, ws, f, *args, **kwargs):
    try:
        jresp = await blocking_to_async(thread_pool, f, *args, **kwargs)
    except Exception:
        log.exception(f'error calling {f.__name__} for {endpoint}')
        status = 500
        value = traceback.format_exc()
    else:
        status = jresp.status()
        value = jresp.value()
    log.info(f'{endpoint}: response status {status} value {value}')
    await ws.send_json({'status': status, 'value': value})


async def add_user(app, userdata):
    username = userdata['username']
    users = app['users']
    if username in users:
        return

    jbackend = app['jbackend']
    k8s_client = app['k8s_client']
    gsa_key_secret = await retry_transient_errors(
        k8s_client.read_namespaced_secret,
        userdata['gsa_key_secret_name'],
        DEFAULT_NAMESPACE,
        _request_timeout=5.0)
    gsa_key = base64.b64decode(gsa_key_secret.data['key.json']).decode()
    jbackend.addUser(username, gsa_key)
    users.add(username)


@routes.get('/healthcheck')
async def healthcheck(request):  # pylint: disable=unused-argument
    return web.Response()


def blocking_execute(jbackend, userdata, body):
    return jbackend.execute(userdata['username'], userdata['session_id'], body['billing_project'], body['bucket'], body['code'])


def blocking_load_references_from_dataset(jbackend, userdata, body):
    return jbackend.loadReferencesFromDataset(
        userdata['username'], userdata['session_id'], body['billing_project'], body['bucket'], body['path'])


def blocking_value_type(jbackend, userdata, body):
    return jbackend.valueType(userdata['username'], body['code'])


def blocking_table_type(jbackend, userdata, body):
    return jbackend.tableType(userdata['username'], body['code'])


def blocking_matrix_type(jbackend, userdata, body):
    return jbackend.matrixTableType(userdata['username'], body['code'])


def blocking_blockmatrix_type(jbackend, userdata, body):
    return jbackend.blockMatrixType(userdata['username'], body['code'])


def blocking_get_reference(jbackend, userdata, body):   # pylint: disable=unused-argument
    return jbackend.referenceGenome(userdata['username'], body['name'])


async def handle_ws_response(request, userdata, endpoint, f):
    app = request.app
    jbackend = app['jbackend']

    await add_user(app, userdata)
    log.info(f'{endpoint}: connecting websocket')
    ws = web.WebSocketResponse(heartbeat=30, max_msg_size=0)
    task = None
    await ws.prepare(request)
    try:
        log.info(f'{endpoint}: websocket prepared {ws}')
        body = await ws.receive_json()
        log.info(f'{endpoint}: {body}')
        task = asyncio.ensure_future(send_ws_response(app['thread_pool'], endpoint, ws, f, jbackend, userdata, body))
        r = await ws.receive()
        log.info(f'{endpoint}: Received websocket message. Expected CLOSE, got {r}')
        return ws
    finally:
        if not ws.closed:
            await ws.close()
            log.info(f'{endpoint}: Websocket was not closed. Closing.')
        if task is not None and not task.done():
            task.cancel()
            log.info(f'{endpoint}: Task has been cancelled due to websocket closure.')
        log.info(f'{endpoint}: websocket connection closed')


@routes.get('/api/v1alpha/execute')
@rest_authenticated_users_only
async def execute(request, userdata):
    return await handle_ws_response(request, userdata, 'execute', blocking_execute)


@routes.get('/api/v1alpha/load_references_from_dataset')
@rest_authenticated_users_only
async def load_references_from_dataset(request, userdata):
    return await handle_ws_response(request, userdata, 'load_references_from_dataset', blocking_load_references_from_dataset)


@routes.get('/api/v1alpha/type/value')
@rest_authenticated_users_only
async def value_type(request, userdata):
    return await handle_ws_response(request, userdata, 'type/value', blocking_value_type)


@routes.get('/api/v1alpha/type/table')
@rest_authenticated_users_only
async def table_type(request, userdata):
    return await handle_ws_response(request, userdata, 'type/table', blocking_table_type)


@routes.get('/api/v1alpha/type/matrix')
@rest_authenticated_users_only
async def matrix_type(request, userdata):
    return await handle_ws_response(request, userdata, 'type/matrix', blocking_matrix_type)


@routes.get('/api/v1alpha/type/blockmatrix')
@rest_authenticated_users_only
async def blockmatrix_type(request, userdata):
    return await handle_ws_response(request, userdata, 'type/blockmatrix', blocking_blockmatrix_type)


@routes.get('/api/v1alpha/references/get')
@rest_authenticated_users_only
async def get_reference(request, userdata):  # pylint: disable=unused-argument
    return await handle_ws_response(request, userdata, 'references/get', blocking_get_reference)


@routes.get('/api/v1alpha/flags/get')
@rest_authenticated_developers_only
async def get_flags(request, userdata):  # pylint: disable=unused-argument
    app = request.app
    jresp = await blocking_to_async(app['thread_pool'], app['jbackend'].flags)
    return java_to_web_response(jresp)


@routes.get('/api/v1alpha/flags/get/{flag}')
@rest_authenticated_developers_only
async def get_flag(request, userdata):  # pylint: disable=unused-argument
    app = request.app
    f = request.match_info['flag']
    jresp = await blocking_to_async(app['thread_pool'], app['jbackend'].getFlag, f)
    return java_to_web_response(jresp)


@routes.get('/api/v1alpha/flags/set/{flag}')
@rest_authenticated_developers_only
async def set_flag(request, userdata):  # pylint: disable=unused-argument
    app = request.app
    f = request.match_info['flag']
    v = request.query.get('value')
    if v is None:
        jresp = await blocking_to_async(app['thread_pool'], app['jbackend'].unsetFlag, f)
    else:
        jresp = await blocking_to_async(app['thread_pool'], app['jbackend'].setFlag, f, v)
    return java_to_web_response(jresp)


@routes.get('/api/v1alpha/version')
async def rest_get_version(request):  # pylint: disable=W0613
    try:
        return web.Response(text=version())
    except Exception as e:
        return web.json_response({"error": str(e)})


async def on_startup(app):
    thread_pool = concurrent.futures.ThreadPoolExecutor(max_workers=16)
    app['thread_pool'] = thread_pool

    spark_home = find_spark_home()
    port = launch_gateway(die_on_exit=True, classpath=f'{spark_home}/jars/*:/hail.jar')
    gateway = JavaGateway(
        gateway_parameters=GatewayParameters(port=port),
        auto_convert=True)
    app['gateway'] = gateway

    hail_pkg = getattr(gateway.jvm, 'is').hail
    app['hail_pkg'] = hail_pkg

    jbackend = hail_pkg.backend.service.ServiceBackend.apply()
    app['jbackend'] = jbackend

    jhc = hail_pkg.HailContext.apply(
        jbackend, 'hail.log', False, False, 50, False, 3)
    app['jhc'] = jhc

    app['users'] = set()

    kube.config.load_incluster_config()
    k8s_client = kube.client.CoreV1Api()
    app['k8s_client'] = k8s_client


async def on_cleanup(app):
    del app['k8s_client']
    await asyncio.wait(*(t for t in asyncio.all_tasks() if t is not asyncio.current_task()))


async def on_shutdown(app):
    # Filter the asyncio.current_task(), because if we await
    # the current task we'll end up in a deadlock
    remaining_tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    log.info(f"On shutdown request received, with {len(remaining_tasks)} remaining tasks")
    await asyncio.wait(*remaining_tasks)
    log.info("All tasks on shutdown have completed")


def run():
    app = web.Application()

    setup_aiohttp_session(app)

    app.add_routes(routes)

    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.on_shutdown.append(on_shutdown)

    deploy_config = get_deploy_config()
    web.run_app(
        deploy_config.prefix_application(app, 'query'),
        host='0.0.0.0',
        port=5000,
        access_log_class=AccessLogger,
        ssl_context=internal_server_ssl_context())
