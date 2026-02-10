module infer.config;

struct InferConfig
{
    string endpoint = "http://127.0.0.1:1234/";
    string chatModel = "qwen/qwen3-4b-2507";
    string embedModel = "text-embedding-qwen3-embedding-0.6b";
    float groupingThreshold = 0.75;
    float dedupeThreshold = 0.92;
    int maxMergeChars = 24_000;
    bool autoResolveRabbitHoles = true;
    string[] enabledSources = ["wikipedia"];
}

private __gshared InferConfig _config;

InferConfig config()
{
    return _config;
}

void setConfig(InferConfig cfg)
{
    _config = cfg;
}
