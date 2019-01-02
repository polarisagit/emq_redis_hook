PROJECT = emq_redis_hook
PROJECT_DESCRIPTION = EMQ Redis Hook Plugin
PROJECT_VERSION = 2.3.11

DEPS = eredis ecpool clique
dep_eredis = git https://github.com/emqtt/eredis v1.0.9
dep_ecpool = git https://github.com/emqtt/ecpool v0.3.0
dep_clique = git https://github.com/emqtt/clique v0.3.10

BUILD_DEPS = emqttd cuttlefish
dep_emqttd = git https://github.com/emqtt/emqttd v2.3.11
dep_cuttlefish = git https://github.com/emqtt/cuttlefish v2.0.11

ERLC_OPTS += +debug_info
ERLC_OPTS += +'{parse_transform, lager_transform}'

TEST_DEPS = emqttc
dep_emqttc = git https://github.com/emqtt/emqttc

TEST_ERLC_OPTS += +debug_info
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

COVER = true

include erlang.mk

app:: rebar.config

app.config::
	deps/cuttlefish/cuttlefish -l info -e etc/ -c etc/emq_redis_hook.conf -i priv/emq_redis_hook.schema -d data
