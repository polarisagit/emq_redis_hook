
emq-redis-hook
============

EMQ broker plugin to catch broker hooks through redis.<br>
[http://emqtt.io](http://emqtt.io)<br>


Build Plugin
-----

Add the plugin into emq-relx [v2.3.11](https://github.com/emqx/emqx-rel/tree/v2.3.11) ：

Makefile：

```
DEPS += emq_redis_hook 

dep_emq_redis_hook  = git https://github.com/polarisagit/emq_redis_hook v2.3.11
```

relx.config：

```
{emq_redis_hook, load} 
```



# emq_redis_hook.conf 

##Redis server address.

redis.hook.server = 192.168.15.121:19000

##Redis pool size.  (ecpool)  Value: Number

redis.hook.pool = 64

##Redis database no. Value: Number


redis.hook.database = 15

##Redis password. Value: String . 

##If  set default values for password , not call AUTH cmd

##If want AUTH , modify the bug: eredis eredis_client.erl start_link need modify AUTH "Password" to AUTH Password for redis and codis3.X 

redis.hook.password = 123

##Redis message key.(connected and disconnected use “LINE:、CONNECTED: ” other use “emqmessage” ) Value: String

redis.hook.message.key = emqmessage

##The Redis Hook Rules.

redis.hook.rule.client.connected.1     = {"action": "on_client_connected"}

redis.hook.rule.client.disconnected.1  = {"action": "on_client_disconnected"}

#redis.hook.rule.client.subscribe.1     = {"action": "on_client_subscribe"}

#redis.hook.rule.client.unsubscribe.1   = {"action": "on_client_unsubscribe"}

#redis.hook.rule.session.created.1      = {"action": "on_session_created"}

#redis.hook.rule.session.subscribed.1   = {"action": "on_session_subscribed"}

#redis.hook.rule.session.unsubscribed.1 = {"action": "on_session_unsubscribed"}

#redis.hook.rule.session.terminated.1   = {"action": "on_session_terminated"}

#redis.hook.rule.message.publish.1      = {"action": "on_message_publish"}

#redis.hook.rule.message.delivered.1    = {"action": "on_message_delivered"}

#redis.hook.rule.message.acked.1        = {"action": "on_message_acked"}

# emq_redis_hook
