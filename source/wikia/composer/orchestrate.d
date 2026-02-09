module wikia.composer.orchestrate;

import std.net.curl : HTTP;
import std.uri : encode;
import std.array : join, replace;
import std.datetime : SysTime, Clock, Duration;
import core.thread : Thread;
import core.time : dur;

struct Orchestrator
{
    string host;
    long minIntervalMs;
    private HTTP _http;
    private bool _initialized;
    private SysTime _lastRequestTime;

    HTTP client()
    {
        if (!_initialized)
        {
            _http = HTTP();
            _initialized = true;
        }
        return _http;
    }

    void rateLimit()
    {
        if (_lastRequestTime == SysTime.init)
        {
            _lastRequestTime = Clock.currTime();
            return;
        }

        Duration minInterval = dur!"msecs"(minIntervalMs);
        Duration elapsed = Clock.currTime() - _lastRequestTime;
        if (elapsed < minInterval)
            Thread.sleep(minInterval - elapsed);

        _lastRequestTime = Clock.currTime();
    }

    string buildURL(string path, string[string] queryParams = null)
    {
        string url = host~path;
        if (queryParams.length > 0)
        {
            string[] pairs;
            foreach (k, v; queryParams)
                pairs ~= encode(k)~"="~encode(v).replace("+", "%2B");
            url ~= "?"~pairs.join("&");
        }
        return url;
    }
}
