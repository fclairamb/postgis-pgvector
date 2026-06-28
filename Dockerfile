# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
#
# postgis-pgvector — PostgreSQL + PostGIS + pgvector, built from a pinned Debian.
#
# Rather than layering on a prebuilt postgres/postgis image, this reconstructs
# the official postgres image (https://github.com/docker-library/postgres,
# 18/trixie) on top of a pinned Debian snapshot, then adds PostGIS the way
# https://github.com/postgis/docker-postgis (18-3.6) does, then builds pgvector.
#
# The postgres/PostGIS blocks below are vendored verbatim from those upstreams
# (trimmed to the amd64/arm64 binary path) so behaviour matches the official
# images exactly. Only the base image differs.
#
# Pinned, reproducible inputs:
#   * Debian base ......... debian:trixie-20260623-slim   (this FROM)
#   * PostgreSQL .......... ENV PG_VERSION                  (PGDG apt)
#   * PostGIS ............. ENV POSTGIS_VERSION             (PGDG apt)
#   * gosu ................ ENV GOSU_VERSION                (GitHub release)
#   * pgvector ............ ARG PGVECTOR_VERSION            (built from source)
# Renovate tracks the base image, gosu and pgvector; PG_VERSION / POSTGIS_VERSION
# are apt-pinned and bumped by hand (or picked up by the weekly rebuild). See
# renovate.json and README.md. Versioning (image tag) is computed in CI from
# PG_VERSION — see .github/workflows/release.yml.

FROM debian:trixie-20260623-slim@sha256:28de0877c2189802884ccd20f15ee41c203573bd87bb6b883f5f46362d24c5c2

# ===========================================================================
# Below, verbatim from docker-library/postgres 18/trixie (amd64/arm64 path)
# ===========================================================================

# explicitly set user/group IDs
RUN set -eux; \
	groupadd -r postgres --gid=999; \
# https://salsa.debian.org/postgresql/postgresql-common/blob/997d842ee744687d99a2b2d95c1083a2615c79e8/debian/postgresql-common.postinst#L32-35
	useradd -r -g postgres --uid=999 --home-dir=/var/lib/postgresql --shell=/bin/bash postgres; \
# also create the postgres user's home directory with appropriate permissions
# see https://github.com/docker-library/postgres/issues/274
	install --verbose --directory --owner postgres --group postgres --mode 1777 /var/lib/postgresql

RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		gnupg \
		less \
	; \
	rm -rf /var/lib/apt/lists/*

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION=1.19
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ca-certificates wget; \
	rm -rf /var/lib/apt/lists/*; \
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true

# make the "en_US.UTF-8" locale so postgres will be utf-8 enabled by default
RUN set -eux; \
	if [ -f /etc/dpkg/dpkg.cfg.d/docker ]; then \
		grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
		sed -ri '/\/usr\/share\/locale/d' /etc/dpkg/dpkg.cfg.d/docker; \
		! grep -q '/usr/share/locale' /etc/dpkg/dpkg.cfg.d/docker; \
	fi; \
	apt-get update; apt-get install -y --no-install-recommends locales; rm -rf /var/lib/apt/lists/*; \
	echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; \
	locale-gen; \
	locale -a | grep 'en_US.utf8'
ENV LANG=en_US.utf8

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libnss-wrapper \
		xz-utils \
		zstd \
	; \
	rm -rf /var/lib/apt/lists/*

RUN mkdir /docker-entrypoint-initdb.d

RUN set -ex; \
# pub   4096R/ACCC4CF8 2011-10-13 [expires: 2019-07-02]
#       Key fingerprint = B97B 0AFC AA1A 47F0 44F2  44A0 7FCC 7D46 ACCC 4CF8
# uid                  PostgreSQL Debian Repository
	key='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'; \
	export GNUPGHOME="$(mktemp -d)"; \
	mkdir -p /usr/local/share/keyrings/; \
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
	gpg --batch --export --armor "$key" > /usr/local/share/keyrings/postgres.gpg.asc; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME"

ENV PG_MAJOR=18
ENV PATH=$PATH:/usr/lib/postgresql/$PG_MAJOR/bin

ENV PG_VERSION=18.4-1.pgdg13+1

RUN set -ex; \
	export PYTHONDONTWRITEBYTECODE=1; \
	aptRepo="[ signed-by=/usr/local/share/keyrings/postgres.gpg.asc ] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main $PG_MAJOR"; \
	echo "deb $aptRepo" > /etc/apt/sources.list.d/pgdg.list; \
	apt-get update; \
	\
	apt-get install -y --no-install-recommends postgresql-common; \
	sed -ri 's/#(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
	apt-get install -y --no-install-recommends \
		"postgresql-$PG_MAJOR=$PG_VERSION" \
	; \
# https://github.com/docker-library/postgres/pull/1344#issuecomment-2936578203 (JIT is a separate package in 18+, but only supported for a subset of architectures)
	if apt-get install -s "postgresql-$PG_MAJOR-jit" > /dev/null 2>&1; then \
		apt-get install -y --no-install-recommends "postgresql-$PG_MAJOR-jit=$PG_VERSION"; \
	fi; \
	\
	rm -rf /var/lib/apt/lists/*; \
# some of the steps above generate a lot of "*.pyc" files, so we clean them up manually (as long as they aren't owned by a package)
	find /usr -name '*.pyc' -type f -exec bash -c 'for pyc; do dpkg -S "$pyc" &> /dev/null || rm -vf "$pyc"; done' -- '{}' +; \
	\
	postgres --version

# make the sample config easier to munge (and "correct by default")
RUN set -eux; \
	dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample"; \
	cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
	ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_MAJOR/"; \
	sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/share/postgresql/postgresql.conf.sample; \
	grep -F "listen_addresses = '*'" /usr/share/postgresql/postgresql.conf.sample

RUN install --verbose --directory --owner postgres --group postgres --mode 3777 /var/run/postgresql

# NOTE: in 18+, PGDATA matches the pg_ctlcluster standard directory structure,
# and the VOLUME has moved from /var/lib/postgresql/data to /var/lib/postgresql
ENV PGDATA=/var/lib/postgresql/18/docker
VOLUME /var/lib/postgresql

# ===========================================================================
# PostGIS — verbatim from postgis/docker-postgis 18-3.6
# ===========================================================================
ENV POSTGIS_MAJOR=3
ENV POSTGIS_VERSION=3.6.4+dfsg-2.pgdg13+1
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		# ca-certificates: for accessing remote raster files; build dep purged above re-added here for runtime
		ca-certificates \
		postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR=$POSTGIS_VERSION \
		postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts \
	&& rm -rf /var/lib/apt/lists/*

# ===========================================================================
# pgvector — built from a pinned source tag (Renovate tracks it)
# ===========================================================================
# https://github.com/pgvector/pgvector/tags
ARG PGVECTOR_VERSION=0.8.3
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		build-essential \
		git \
		"postgresql-server-dev-$PG_MAJOR" \
	; \
	git clone --branch "v${PGVECTOR_VERSION}" --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector; \
	cd /tmp/pgvector; \
# OPTFLAGS="" keeps the build portable; with_llvm=no avoids LLVM/clang version matching
	make OPTFLAGS="" with_llvm=no; \
	make OPTFLAGS="" with_llvm=no install; \
	cd /; \
	rm -rf /tmp/pgvector; \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# init scripts: PostGIS (sourced, so it can use the entrypoint's psql array) then
# pgvector (executable). 10_ before 20_ so template_postgis exists first.
COPY initdb-postgis.sh /docker-entrypoint-initdb.d/10_postgis.sh
COPY initdb-pgvector.sh /docker-entrypoint-initdb.d/20_pgvector.sh
COPY update-postgis.sh /usr/local/bin/

# ===========================================================================
# Entrypoint — verbatim from docker-library/postgres 18/trixie
# ===========================================================================
COPY docker-entrypoint.sh docker-ensure-initdb.sh /usr/local/bin/
RUN ln -sT docker-ensure-initdb.sh /usr/local/bin/docker-enforce-initdb.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# SIGINT = PostgreSQL "Fast Shutdown mode"; see
# https://www.postgresql.org/docs/current/server-shutdown.html
STOPSIGNAL SIGINT
EXPOSE 5432
CMD ["postgres"]
