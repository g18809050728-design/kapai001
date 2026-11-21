import os

from kapai.db import make_engine

ORIGIN = os.environ["KAPAI_ORIGIN"].rstrip("/")
engine = make_engine()


def enabled(feature):
    return os.getenv("KAPAI_" + feature, "0") == "1"
