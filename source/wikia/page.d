// module wikia.page;

// import std.regex;
// import std.string : strip;
// import wikia.psychonaut : Psychonaut;
// import wikia.wikipedia : Wikipedia;

// class Page
// {
//     string title;
//     string source;
//     string url;
//     Section[] sections;
//     Metadata metadata;
//     string[] authors;
//     string raw;

//     this(string title, string db = "psychonaut")
//     {
//         this.title = title;
//         this.source = db;

//         if (db == "psychonaut")
//         {
//             this.url = "https://psychonautwiki.org/wiki/"~title;
//             Psychonaut.getContent(this);
//         }
//         else if (db == "wikipedia")
//         {
//             this.url = "https://en.wikipedia.org/wiki/"~title;
//             Wikipedia.getContent(this);
//         }
//         else if (db == "pmc")
//         {
//             this.url = "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC"~title;
//         }
//         else
//             throw new Exception("Unknown DB: "~db);
//     }

//     string fulltext() const
//     {
//         import std.array : join;
//         import std.algorithm : map;
//         if (sections.length == 0)
//             return "";
//         return sections.map!(s => s.content).join("\n\n");
//     }

//     string doi() const { return metadata.get("doi"); }
//     string pmid() const { return metadata.get("pmid"); }
//     string pmcId() const { return metadata.get("pmcId"); }
// }

// struct Section
// {
//     string heading;
//     string content;
//     int level;
// }

// struct Metadata
// {
//     string[string] fields;

//     string get(string key) const
//     {
//         if (key in fields)
//             return fields[key];
//         return null;
//     }
// }

// Section[] parseSections(string wikitext)
// {
//     Section[] ret;
//     if (!wikitext.length)
//         return ret;

//     enum headingRe = ctRegex!(r"(={2,6})\s*([^=]+?)\s*\1");

//     size_t lastEnd;
//     string lastHeading;
//     int lastLevel;
//     foreach (match; matchAll(wikitext, headingRe))
//     {
//         size_t start = match.pre.length;
//         int level = cast(int)match[1].length;
//         string heading = match[2].strip;

//         if (lastHeading.length)
//             ret ~= Section(lastHeading, wikitext[lastEnd..start].strip, lastLevel);

//         lastHeading = heading;
//         lastLevel = level;
//         lastEnd = start + match.hit.length;
//     }

//     if (lastHeading.length)
//         ret ~= Section(lastHeading, wikitext[lastEnd..$].strip, lastLevel);

//     return ret;
// }

// Metadata parseMetadata(string wikitext)
// {
//     Metadata ret;
//     if (!wikitext.length)
//         return ret;

//     enum templateRe = ctRegex!(r"\{\{([^}]+)\}\}");
//     enum pairRe = ctRegex!(r"\|\s*([^=\s]+)\s*=\s*([^|]*)");

//     foreach (match; matchAll(wikitext, templateRe))
//     {
//         foreach (pairMatch; matchAll(match[1], pairRe))
//             ret.fields[pairMatch[1].strip] = pairMatch[2].strip;
//     }

//     return ret;
// }