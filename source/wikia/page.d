module wikia.page;

import std.regex;
import std.string : strip;
import std.array : replace;

struct Section
{
    string heading;
    string content;
    int level;
}

class Page
{
package:
    string _raw;
    Section[] _sections;
    void delegate(Page) _fetchContent;

    this() { }

    this(
        string title, 
        string source, 
        string url,
        void delegate(Page) fetchContent
    )
    {
        this.title = title;
        this.source = source;
        this.url = url;
        this._fetchContent = fetchContent;
    }

public:
    string title;
    string source;
    string url;

    ref string raw()
    {
        if (_raw is null && _fetchContent !is null)
        {
            _fetchContent(this);
            _fetchContent = null;
        }
        return _raw;
    }

    Section[] sections()
    {
        if (_sections.length == 0 && raw !is null)
            _sections = parseSections(_raw);

        return _sections;
    }

    string fulltext() const
    {
        import std.array : join;
        import std.algorithm : map;
        if (_sections.length == 0)
            return "";
        return _sections.map!(s => s.content).join("\n\n");
    }

    string preamble()
    {
        if (raw is null)
            return "";
        return parsePreamble(_raw);
    }
}

Section[] parseSections(string wikitext)
{
    Section[] ret;
    if (!wikitext.length)
        return ret;

    enum headingRe = ctRegex!(r"(={2,6})\s*([^=]+?)\s*\1");

    size_t lastEnd;
    string lastHeading;
    int lastLevel;
    foreach (match; matchAll(wikitext, headingRe))
    {
        size_t start = match.pre.length;
        int level = cast(int) match[1].length;
        string heading = match[2].strip;

        if (lastHeading.length)
            ret ~= Section(lastHeading,
                wikitext[lastEnd..start].strip, lastLevel);

        lastHeading = heading;
        lastLevel = level;
        lastEnd = start + match.hit.length;
    }

    if (lastHeading.length)
        ret ~= Section(lastHeading,
            wikitext[lastEnd..$].strip, lastLevel);

    return ret;
}

string parsePreamble(string wikitext)
{
    if (!wikitext.length)
        return "";

    enum headingRe = ctRegex!(r"(={2,6})\s*([^=]+?)\s*\1");
    auto m = matchFirst(wikitext, headingRe);
    if (m.empty)
        return cleanWikitext(wikitext.strip);

    string pre = wikitext[0..m.pre.length].strip;
    return pre.length > 0 ? cleanWikitext(pre) : "";
}

string cleanWikitext(string text)
{
    if (text is null || text.length == 0)
        return "";

    // Remove categories
    enum catRe = ctRegex!(`\[\[Category:[^\]]*\]\]`);
    foreach (m; matchAll(text, catRe))
        text = text.replace(m.hit, "");

    // Remove HTML comments
    enum commentRe = ctRegex!(`<!--[\s\S]*?-->`);
    foreach (m; matchAll(text, commentRe))
        text = text.replace(m.hit, "");

    // Remove ref tags
    enum refRe = ctRegex!(`</?ref[^>]*>`);
    foreach (m; matchAll(text, refRe))
        text = text.replace(m.hit, "");

    // Convert wiki links [[target|display]] -> display, [[target]] -> target
    enum linkRe = ctRegex!(`\[\[([^\]|]+)(?:\|([^\]]+))?\]\]`);
    foreach (m; matchAll(text, linkRe))
    {
        string display = m[2].length > 0 ? m[2] : m[1];
        text = text.replace(m.hit, display);
    }

    // Remove bold/italic markup
    text = text.replace("'''''", "");
    text = text.replace("'''", "");
    text = text.replace("''", "");

    // Convert &nbsp; to space
    text = text.replace("&nbsp;", " ");

    return text.strip;
}