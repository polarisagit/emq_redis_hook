
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



# emq_redis_hook
