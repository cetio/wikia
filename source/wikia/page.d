module wikia.page;

import std.regex;
import std.string : strip;

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

public:
    string title;
    string source;
    string url;

    this(string title, string source, string url,
        void delegate(Page) fetchContent)
    {
        this.title = title;
        this.source = source;
        this.url = url;
        this._fetchContent = fetchContent;
    }

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
                wikitext[lastEnd .. start].strip, lastLevel);

        lastHeading = heading;
        lastLevel = level;
        lastEnd = start + match.hit.length;
    }

    if (lastHeading.length)
        ret ~= Section(lastHeading,
            wikitext[lastEnd .. $].strip, lastLevel);

    return ret;
}