from pathlib import Path
import obspython as S
import redis
from types import SimpleNamespace as _G
from ctypes import *
from ctypes.util import find_library
import os


G = _G()
G.obsffi = CDLL(find_library("obs"))
G.obsffi_front = CDLL(find_library("obs-frontend-api"))


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


redis_config = {
    "host": '192.168.31.15',
    "port": 6379,
    "database": 0
}


def get_rec_path() -> str:
    cfg = G.obs_frontend_get_profile_config()
    e = lambda x: x.encode("utf-8")
    return G.config_get_string(cfg, e("AdvOut"), e("RecFilePath")).decode("utf-8")


def get_recorded_file():
    base_path = Path(get_rec_path())
    print(base_path)
    list = os.listdir(base_path)
    list.sort(key=lambda fileName: os.path.getmtime(base_path / fileName))
    print(list[-1])
    return base_path / list[-1]


def handle_rec_pause():
    sh = S.obs_output_get_signal_handler(S.obs_frontend_get_recording_output())
    S.signal_handler_connect(sh, "pause", rec_pause_callback)


def handle_rec_stop():
    sh = S.obs_output_get_signal_handler(S.obs_frontend_get_recording_output())
    S.signal_handler_connect(sh, "stop", rec_stop_callback)


def rec_pause_callback(calldata):
    print(calldata)
    #out = S.calldata_ptr(calldata, "output") # bad type
    print('output paused')
    r = redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database'])
    r.set('obs:record', 'paused')


def rec_stop_callback(calldata):
    record_path = get_recorded_file()
    print('output stop')
    r = redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database'])
    r.set('obs:record', 'stop')
    r.xadd('stream-video-render', {'file': str(record_path)})
    redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database']).set('obs:record', 'stop')


def on_load(event):
    print("1 execute on load")
    print(event)
    # if event == S.OBS_FRONTEND_EVENT_RECORDING_STARTED:
    #     handle_rec_pause()


def script_load(settings):
    print("0 script loaded")
    S.obs_frontend_add_event_callback(on_load)
    handle_rec_pause()
    handle_rec_stop()
    redis.StrictRedis(host=redis_config['host'], port=redis_config['port'], db=redis_config['database']).set('obs:status', 'load')