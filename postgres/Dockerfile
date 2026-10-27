# =====================================================================
#  Imagen de PostgreSQL 16 con las dos extensiones FDW instaladas:
#    - tds_fdw   : para conectarse a Microsoft SQL Server
#    - mongo_fdw : para conectarse a MongoDB
# =====================================================================
# Debian 13 (trixie): trae libmongoc 1.30, la version que pide mongo_fdw
FROM postgres:16-trixie

# Vincula la imagen publicada en GitHub Container Registry con el repositorio
LABEL org.opencontainers.image.source="https://github.com/Danny7w7-coder/proyecto2Bases2"
LABEL org.opencontainers.image.description="PostgreSQL 16 con tds_fdw y mongo_fdw - Proyecto 2 Bases de Datos II"

# 1) tds_fdw viene empaquetado en el repositorio oficial de PostgreSQL (PGDG)
#    e instala tambien FreeTDS (la libreria que habla el protocolo de SQL Server).
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-16-tds-fdw \
        freetds-common \
    && rm -rf /var/lib/apt/lists/*

# Para que los acentos (José, Cartago...) viajen bien desde SQL Server
RUN printf '[global]\n\ttds version = 7.4\n\tclient charset = UTF-8\n' > /etc/freetds/freetds.conf
# Formato de fecha ISO; sin esto FreeTDS manda "Sep  2 2026 12:00:00:AM"
RUN printf '[default]\n\tdate format = %%Y-%%m-%%d %%H:%%M:%%S.%%z\n' > /etc/freetds/locales.conf

# 2) mongo_fdw se compila desde el codigo fuente (EnterpriseDB).
#    - El driver de MongoDB (libmongoc) se compila en la version 1.30.2,
#      que es la que usa mongo_fdw (la de Debian trae parches que rompen
#      las lecturas).
#    - La libreria json-c se descarga y solo se "configura" con cmake,
#      porque el Makefile de mongo_fdw compila sus archivos por dentro.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git cmake wget pkg-config ca-certificates \
        libssl-dev libssl3t64 \
        postgresql-server-dev-16 \
    && cd /tmp \
    && wget -q https://github.com/mongodb/mongo-c-driver/releases/download/1.30.2/mongo-c-driver-1.30.2.tar.gz \
    && tar -zxf mongo-c-driver-1.30.2.tar.gz \
    && cd mongo-c-driver-1.30.2 \
    && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
             -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_STATIC=OFF \
             -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF -DENABLE_SSL=OPENSSL \
             -DENABLE_SASL=OFF -DENABLE_ZSTD=OFF -DENABLE_SNAPPY=OFF -DENABLE_SRV=OFF \
             -DENABLE_MONGODB_AWS_AUTH=OFF > /dev/null \
    && cmake --build build -j"$(nproc)" > /dev/null \
    && cmake --install build > /dev/null \
    && ldconfig \
    && cd /tmp && rm -rf mongo-c-driver-1.30.2* \
    && git clone --depth 1 --branch REL-5_5_3 https://github.com/EnterpriseDB/mongo_fdw.git /tmp/mongo_fdw \
    && cd /tmp/mongo_fdw \
    && wget -q https://github.com/json-c/json-c/archive/json-c-0.18-20240915.tar.gz \
    && tar -zxf json-c-0.18-20240915.tar.gz \
    && mv json-c-json-c-0.18-20240915 json-c \
    && (cd json-c && cmake -DDISABLE_EXTRA_LIBS=ON . > /dev/null) \
    && make USE_PGXS=1 \
    && make USE_PGXS=1 install \
    && cd / && rm -rf /tmp/mongo_fdw \
    && apt-mark manual libssl3t64 \
    && apt-get purge -y build-essential git cmake wget postgresql-server-dev-16 libssl-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*
