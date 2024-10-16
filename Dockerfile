FROM denoland/deno:bin-1.39.0 AS deno

FROM ubuntu:22.04
LABEL description="Docker Container for the Swift programming language"

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update && \
    apt-get -q install -y \
    binutils \
    git \
    unzip \
    gnupg2 \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-11-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-11-dev \
    libxml2-dev \
    libz3-dev \
    pkg-config \
    python3-lldb-13 \
    tzdata \
    zlib1g-dev \
    && rm -r /var/lib/apt/lists/*

# Everything up to here should cache nicely between Swift versions, assuming dev dependencies change little

# pub   4096R/ED3D1561 2019-03-22 [SC] [expires: 2023-03-23]
#       Key fingerprint = A62A E125 BBBF BB96 A6E0  42EC 925C C1CC ED3D 1561
# uid                  Swift 5.x Release Signing Key <swift-infrastructure@swift.org
ARG SWIFT_SIGNING_KEY=A62AE125BBBFBB96A6E042EC925CC1CCED3D1561
ARG SWIFT_PLATFORM=ubuntu22.04
ARG SWIFT_BRANCH=swift-5.10-release
ARG SWIFT_VERSION=swift-5.10-RELEASE
ARG SWIFT_WEBROOT=https://download.swift.org

ENV SWIFT_SIGNING_KEY=$SWIFT_SIGNING_KEY \
    SWIFT_PLATFORM=$SWIFT_PLATFORM \
    SWIFT_BRANCH=$SWIFT_BRANCH \
    SWIFT_VERSION=$SWIFT_VERSION \
    SWIFT_WEBROOT=$SWIFT_WEBROOT

RUN set -e; \
    ARCH_NAME="$(dpkg --print-architecture)"; \
    url=; \
    case "${ARCH_NAME##*-}" in \
        'amd64') \
            OS_ARCH_SUFFIX=''; \
            ;; \
        'arm64') \
            OS_ARCH_SUFFIX='-aarch64'; \
            ;; \
        *) echo >&2 "error: unsupported architecture: '$ARCH_NAME'"; exit 1 ;; \
    esac; \
    SWIFT_WEBDIR="$SWIFT_WEBROOT/$SWIFT_BRANCH/$(echo $SWIFT_PLATFORM | tr -d .)$OS_ARCH_SUFFIX" \
    && SWIFT_BIN_URL="$SWIFT_WEBDIR/$SWIFT_VERSION/$SWIFT_VERSION-$SWIFT_PLATFORM$OS_ARCH_SUFFIX.tar.gz" \
    && SWIFT_SIG_URL="$SWIFT_BIN_URL.sig" \
    # - Grab curl here so we cache better up above
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -q update && apt-get -q install -y curl && rm -rf /var/lib/apt/lists/* \
    # - Download the GPG keys, Swift toolchain, and toolchain signature, and verify.
    && export GNUPGHOME="$(mktemp -d)" \
    && curl -fsSL "$SWIFT_BIN_URL" -o swift.tar.gz "$SWIFT_SIG_URL" -o swift.tar.gz.sig \
    # - Unpack the toolchain, set libs permissions, and clean up.
    && tar -xzf swift.tar.gz --directory / --strip-components=1 \
    && chmod -R o+r /usr/lib/swift \
    && rm -rf "$GNUPGHOME" swift.tar.gz.sig swift.tar.gz \
    && apt-get purge --auto-remove -y curl

WORKDIR /app

COPY ./_Packages/ ./swiftfiddle.com/_Packages/
RUN rm -rf LICENSE README.md ./_Packages/ 
RUN cd ./swiftfiddle.com/_Packages/ \
    && swift build -c release \
    && rm -rf .build/repositories/

RUN echo 'int isatty(int fd) { return 1; }' | \
  clang -O2 -fpic -shared -ldl -o faketty.so -xc -
RUN strip faketty.so && chmod 400 faketty.so

COPY --from=deno /deno /usr/local/bin/deno

COPY deps.ts .
RUN deno cache deps.ts

ADD . .
RUN deno cache main.ts

EXPOSE 8000
CMD ["deno", "run", "--allow-net", "--allow-run", "main.ts"]
