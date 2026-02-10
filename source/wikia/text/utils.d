module wikia.text.utils;

import std.string : indexOf;

/// Find the matching close delimiter for a nested open/close pair,
/// starting from `start` with depth 1. Returns -1 if not found.
ptrdiff_t findMatchingClose(string text, size_t start, string open, string close)
{
    int depth = 1;
    size_t j = start;
    while (j + close.length <= text.length)
    {
        if (text[j..j + close.length] == close)
        {
            depth--;
            if (depth == 0)
                return cast(ptrdiff_t) j;
            j += close.length;
        }
        else if (j + open.length <= text.length && text[j..j + open.length] == open)
        {
            depth++;
            j += open.length;
        }
        else
            j++;
    }
    return -1;
}

/// Remove all XML/HTML tags from text, leaving only text content.
string stripTags(string text)
{
    if (text.length == 0)
        return text;

    string ret;
    size_t i = 0;
    size_t start = 0;
    while (i < text.length)
    {
        if (text[i] == '<')
        {
            if (i > start)
                ret ~= text[start..i];
            while (i < text.length && text[i] != '>')
                i++;
            if (i < text.length) i++;
            start = i;
        }
        else
            i++;
    }
    if (start < text.length)
        ret ~= text[start..$];
    return ret;
}

/// Decode common XML/HTML entities in text.
string decodeEntities(string text)
{
    if (text.length == 0)
        return text;

    // Quick check: if no '&', return as-is.
    if (text.indexOf('&') < 0)
        return text;

    string ret;
    size_t i = 0;
    size_t start = 0;
    while (i < text.length)
    {
        if (text[i] == '&')
        {
            if (i > start)
                ret ~= text[start..i];

            size_t semicol = i + 1;
            while (semicol < text.length && semicol < i + 12 && text[semicol] != ';')
                semicol++;

            if (semicol < text.length && text[semicol] == ';')
            {
                string entity = text[i + 1..semicol];
                if (entity == "amp") ret ~= "&";
                else if (entity == "lt") ret ~= "<";
                else if (entity == "gt") ret ~= ">";
                else if (entity == "quot") ret ~= "\"";
                else if (entity == "apos") ret ~= "'";
                else if (entity == "nbsp") ret ~= " ";
                else if (entity == "ndash") ret ~= "\u2013";
                else if (entity == "mdash") ret ~= "\u2014";
                else if (entity == "minus") ret ~= "\u2212";
                else
                    ret ~= text[i..semicol + 1];

                i = semicol + 1;
                start = i;
            }
            else
            {
                ret ~= "&";
                i++;
                start = i;
            }
        }
        else
            i++;
    }
    if (start < text.length)
        ret ~= text[start..$];
    return ret;
}
