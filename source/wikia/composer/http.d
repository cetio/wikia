module wikia.composer.http;

import std.net.curl;

void get(
    HTTP http,
    string url,
    void delegate(ubyte[]) success,
    void delegate(ubyte[]) failure)
{
    http.url = url;
    get(http, success, failure);
}

void get(
    HTTP http,
    void delegate(ubyte[]) success,
    void delegate(ubyte[]) failure)
{
    http.method = HTTP.Method.get;

    ubyte[] data;
    http.onReceive((ubyte[] tmp) {
        if (tmp.length > 0)
            data ~= tmp;
        return tmp.length;
    });

    if (http.perform() == 0 && success !is null)
        success(data);
    else if (failure !is null)
        failure(data);
}

void post(
    HTTP http,
    string url,
    string postData,
    void delegate(ubyte[]) success,
    void delegate(ubyte[]) failure)
{
    http.url = url;
    post(http, postData, success, failure);
}

void post(
    HTTP http,
    string postData,
    void delegate(ubyte[]) success,
    void delegate(ubyte[]) failure)
{
    http.method = HTTP.Method.post;
    if (postData !is null)
        http.setPostData(postData, "application/x-www-form-urlencoded");
    else
        http.setPostData("", "application/x-www-form-urlencoded");

    ubyte[] data;
    http.onReceive((ubyte[] tmp) {
        if (tmp.length > 0)
            data ~= tmp;
        return tmp.length;
    });

    if (http.perform() == 0 && success !is null)
        success(data);
    else if (failure !is null)
        failure(data);
}
