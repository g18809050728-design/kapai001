import os

from sqlalchemy import URL, create_engine, event, text


def make_engine():
    url = URL.create(
        "mysql+pymysql",
        username=os.environ["KAPAI_DB_USER"],
        password=os.environ["KAPAI_DB_PASSWORD"],
        host=os.getenv("KAPAI_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("KAPAI_DB_PORT", "3306")),
        database=os.environ["KAPAI_DB_NAME"],
        query={"charset": "utf8mb4"},
    )
    options = {"connect_timeout": 5, "read_timeout": 10, "write_timeout": 10}
    if socket := os.getenv("KAPAI_DB_SOCKET"):
        options["unix_socket"] = socket
    engine = create_engine(url, connect_args=options, pool_pre_ping=True, hide_parameters=True)

    @event.listens_for(engine, "connect")
    def use_utc(connection, _record):
        with connection.cursor() as cursor:
            cursor.execute("SET time_zone = '+00:00'")

    return engine


def execute(connection, statement, **data):
    return connection.execute(text(statement), data)


def one(connection, statement, **data):
    return execute(connection, statement, **data).mappings().first()
