# FreeToken のイメージ。既存の seedcore-freetoken:4b94bdc38a46-cu130-v1（freetoken 0.1.2）の
# docker history から作り方を復元したもの。FT_REV だけを替えれば、版以外の条件を揃えて作り直せる。
#
#   0.1.2（前回記事）: FT_REV=4b94bdc38a46a4dfe534e8793126160d56904c44
#   v0.2.0           : FT_REV=127aa0a920ce2ba3c3fedf66e8c31072990df1f6
#
# ビルド: bash configs/freetoken/build_image.sh v0.2.0
FROM nvidia/cuda:13.0.2-devel-ubuntu24.04

ARG FT_REV=127aa0a920ce2ba3c3fedf66e8c31072990df1f6
LABEL ai.florigen.freetoken-prepare=1.0
LABEL org.opencontainers.image.source=https://github.com/FlashML-org/FreeToken
LABEL org.opencontainers.image.revision=${FT_REV}

ENV DEBIAN_FRONTEND=noninteractive CUDA_HOME=/usr/local/cuda MAX_JOBS=4 CMAKE_BUILD_PARALLEL_LEVEL=4 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git build-essential python3 python3-dev python3-venv \
      cmake ninja-build pkg-config libnuma-dev numactl \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/freetoken-venv
ENV PATH=/opt/freetoken-venv/bin:${PATH}

RUN git init /opt/freetoken-src \
    && git -C /opt/freetoken-src remote add origin https://github.com/FlashML-org/FreeToken.git \
    && git -C /opt/freetoken-src fetch --depth 1 origin "${FT_REV}" \
    && git -C /opt/freetoken-src checkout --detach FETCH_HEAD \
    && test "$(git -C /opt/freetoken-src rev-parse HEAD)" = "${FT_REV}"

RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel ninja \
    && python -m pip install --no-cache-dir '/opt/freetoken-src[accel]' \
    && python -m pip check \
    && python -m pip freeze --all > /opt/freetoken-requirements.txt \
    && ft --version

WORKDIR /tmp
ENTRYPOINT []
CMD ["ft", "--version"]
