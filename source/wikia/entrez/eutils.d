// module wikia.entrez.eutils;

// import wikia.composer;
// import std.json : JSONValue, parseJSON;
// import std.uri : encode;
// import std.conv : to;
// import std.string : assumeUTF;
// import std.array : join;

// struct TimeFrame
// {
//     string from;
//     string to;
// }

// class Entrez
// {
//     static Orchestrator orchestrator = Orchestrator("https://eutils.ncbi.nlm.nih.gov/entrez/eutils", 333);

//     static JSONValue esearch(string DB)(
//         string term,
//         int retmax = 20,
//         int retstart = 0,
//         bool usehistory = false,
//         TimeFrame timeframe = TimeFrame.init,
//         string apiKey = null)
//     {
//         JSONValue json;
//         orchestrator.rateLimit();

//         string[string] params = [
//             "db": DB, "term": term,
//             "retmax": retmax.to!string, "retstart": retstart.to!string,
//             "retmode": "json"
//         ];

//         if (usehistory)
//             params["usehistory"] = "y";
//         if (timeframe.from.length > 0 || timeframe.to.length > 0)
//         {
//             params["datetype"] = "pdat";
//             if (timeframe.from.length > 0)
//                 params["mindate"] = timeframe.from;
//             if (timeframe.to.length > 0)
//                 params["maxdate"] = timeframe.to;
//         }
//         if (apiKey !is null && apiKey.length > 0)
//             params["api_key"] = apiKey;

//         string url = orchestrator.buildURL("/esearch.fcgi", params);
//         orchestrator.client.get(url, (ubyte[] data) {
//             json = parseJSON(data.assumeUTF);
//         }, null);
//         return json;
//     }

//     static string efetch(string DB, string RETMODE = "xml")(
//         string id,
//         string rettype = "abstract",
//         string apiKey = null)
//     {
//         return efetch!(DB, RETMODE)([id], rettype, apiKey);
//     }

//     static string efetch(string DB, string RETMODE = "xml")(
//         string[] ids,
//         string rettype,
//         string apiKey = null)
//     {
//         string xml;
//         if (ids.length == 0)
//             return xml;

//         orchestrator.rateLimit();

//         string idParam = ids.join(",");
//         if (ids.length > 200 || idParam.length > 2000)
//         {
//             string postData = "db="~encode(DB)
//                 ~"&retmode="~encode(RETMODE)
//                 ~"&rettype="~encode(rettype)
//                 ~"&id="~encode(idParam);
//             if (apiKey !is null && apiKey.length > 0)
//                 postData ~= "&api_key="~encode(apiKey);

//             orchestrator.client.post(
//                 orchestrator.buildURL("/efetch.fcgi"),
//                 postData,
//                 (ubyte[] data) {
//                     xml = cast(string)data.assumeUTF;
//                 },
//                 null
//             );
//         }
//         else
//         {
//             string[string] params = [
//                 "db": DB, "retmode": RETMODE, "rettype": rettype, "id": idParam
//             ];
//             if (apiKey !is null && apiKey.length > 0)
//                 params["api_key"] = apiKey;

//             string url = orchestrator.buildURL("/efetch.fcgi", params);
//             orchestrator.client.get(url, (ubyte[] data) {
//                 xml = cast(string)data.assumeUTF;
//             }, null);
//         }
//         return xml;
//     }

//     static JSONValue elink(string dbfrom, string dbto)(
//         string id,
//         TimeFrame timeframe = TimeFrame.init,
//         string apiKey = null)
//     {
//         JSONValue json;
//         orchestrator.rateLimit();

//         string[string] params = [
//             "dbfrom": dbfrom, "db": dbto, "id": id, "retmode": "json"
//         ];

//         if (timeframe.from.length > 0)
//             params["mindate"] = timeframe.from;
//         if (timeframe.to.length > 0)
//             params["maxdate"] = timeframe.to;
//         if (apiKey !is null && apiKey.length > 0)
//             params["api_key"] = apiKey;

//         string url = orchestrator.buildURL("/elink.fcgi", params);
//         orchestrator.client.get(url, (ubyte[] data) {
//             json = parseJSON(data.assumeUTF);
//         }, null);
//         return json;
//     }
// }
