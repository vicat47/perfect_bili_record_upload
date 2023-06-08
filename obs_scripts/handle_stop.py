from pathlib import Path
import obspython as S
import redis
from types import SimpleNamespace as _G
from ctypes import *
from ctypes.util import find_library
import os
import json


G = _G()
G.obsffi = CDLL(find_library("obs"))
G.obsffi_front = CDLL(find_library("obs-frontend-api"))


bvid = ''
redis_config = {}


def wrap(funcname, restype, argtypes=None, use_lib=None):
    """Simplify wrapping ctypes functions"""
    if use_lib is not None:
        func = getattr(use_lib, funcname)
    else:
        func = getattr(G.obsffi, funcname)
    func.restype = restype
    if argtypes is not None:
        func.argtypes = argtypes
    G.__dict__[funcname] = func


class Config(Structure):
    pass


wrap("obs_frontend_get_profile_config", POINTER(Config), use_lib=G.obsffi_front)
wrap("config_get_string", c_char_p, argtypes=[POINTER(Config), c_char_p, c_char_p])


def get_rec_path() -> str:
    cfg = G.obs_frontend_get_profile_config()
    e = lambda x: x.encode("utf-8")
    return G.config_get_string(cfg, e("AdvOut"), e("RecFilePath")).decode("utf-8")


def get_recorded_file():
    '''从文件目录获取最新的录制文件
    根据时间升序取最后一个
    '''
    base_path = Path(get_rec_path())
    list = os.listdir(base_path)
    list.sort(key=lambda fileName: os.path.getmtime(base_path / fileName))
    file_path = base_path / list[-1]
    print(f"recorded file in { file_path }")
    return file_path


def handle_rec_pause():
    sh = S.obs_output_get_signal_handler(S.obs_frontend_get_recording_output())
    S.signal_handler_connect(sh, "pause", rec_pause_callback)


def handle_rec_stop():
    sh = S.obs_output_get_signal_handler(S.obs_frontend_get_recording_output())
    S.signal_handler_connect(sh, "stop", rec_stop_callback)


def rec_pause_callback(calldata):
    print('output paused')
    # print(calldata)
    #out = S.calldata_ptr(calldata, "output") # bad type
    r = redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database'])
    r.set('obs:record', 'paused')


def rec_stop_callback(calldata):
    record_path = get_recorded_file()
    print('output stop')
    r = redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database'])
    r.set('obs:record', 'stop')
    json_str = json.dumps({
        'filename': Path(record_path).name,
        'bvid': bvid,
    })
    r.rpush('biliup:render-list', json_str)
    print(f'render append {json_str}')
    # r.xadd('stream-video-render', {'file': str(record_path)})
    # redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database']).set('obs:record', 'stop')


def on_load(event):
    print("1 execute on load")
    # print(event)
    # if event == S.OBS_FRONTEND_EVENT_RECORDING_STARTED:
    #     handle_rec_pause()


def script_load(settings):
    global bvid
    global redis_config
    print("0 script loaded")
    S.obs_frontend_add_event_callback(on_load)
    # 启动时读取属性
    bvid = S.obs_data_get_string(settings, "bvid")
    redis_config['host'] = S.obs_data_get_string(settings, "redis_host")
    redis_config['port'] = S.obs_data_get_int(settings, "redis_port")
    redis_config['database'] = S.obs_data_get_int(settings, "redis_database")
    print(f"loaded config bvid={ bvid }, redis_config={ str(redis_config) }")
    handle_rec_pause()
    handle_rec_stop()
    redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database']).set('obs:status', 'load')


def refresh_config(props, prop, settings):
    global bvid
    bvid_changed = S.obs_data_get_string(settings, "bvid")
    redis_host_changed = S.obs_data_get_string(settings, "redis_host")
    redis_port_changed = S.obs_data_get_int(settings, "redis_port")
    redis_database_changed = S.obs_data_get_int(settings, "redis_database")
    if bvid_changed != '': bvid = bvid_changed
    if redis_host_changed != '': redis_config['host'] = redis_host_changed
    if redis_port_changed != '': redis_config['port'] = redis_port_changed
    if redis_database_changed != '': redis_config['database'] = redis_database_changed


def script_properties():
    props = S.obs_properties_create()
    upload_bvid_input = S.obs_properties_add_text(
        props, "bvid", "BVID will be upload", S.OBS_TEXT_DEFAULT
    )
    redis_host_input = S.obs_properties_add_text(
        props, "redis_host", "redis host", S.OBS_TEXT_DEFAULT
    )
    redis_port_input = S.obs_properties_add_int(
        props, "redis_port", "redis port", 1000, 65535, 1
    )
    redis_database_input = S.obs_properties_add_int(
        props, "redis_database", "redis database", 0, 16, 1
    )
    S.obs_property_set_modified_callback(upload_bvid_input, refresh_config)
    S.obs_property_set_modified_callback(redis_host_input, refresh_config)
    S.obs_property_set_modified_callback(redis_port_input, refresh_config)
    S.obs_property_set_modified_callback(redis_database_input, refresh_config)
    return props


def script_defaults(settings):
    S.obs_data_set_default_string(settings, 'redis_host', '127.0.0.1')
    S.obs_data_set_default_int(settings, 'redis_port', 6379)
    S.obs_data_set_default_int(settings, 'redis_database', 0)