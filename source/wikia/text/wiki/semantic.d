module wikia.text.wiki.semantic;

import std.string : indexOf, lastIndexOf, strip;

import wikia.text.ast;
import wikia.text.wiki : WikitextParser;
import wikia.text.utils : findMatchingClose;

/// Headings: == Heading == through ====== Heading ======
bool tryParseHeading(ref WikitextParser p)
{
    size_t start = p.pos;
    int level = 0;
    while (p.pos + level < p.src.length && p.src[p.pos + level] == '=' && level < 6)
        level++;

    if (level < 2)
        return false;

    size_t headingStart = p.pos + level;
    size_t lineEnd = p.findLineEnd(headingStart);
    size_t closeEnd = lineEnd;
    while (closeEnd > headingStart && p.src[closeEnd - 1] == ' ')
        closeEnd--;
    size_t closeStart = closeEnd;
    while (closeStart > headingStart && p.src[closeStart - 1] == '=')
        closeStart--;

    int closeLevel = cast(int)(closeEnd - closeStart);
    if (closeLevel < 2)
    {
        p.pos = start;
        return false;
    }

    int effectiveLevel = level < closeLevel ? level : closeLevel;

    Node secNode = Node(NodeType.Section);
    secNode.level = cast(ubyte) effectiveLevel;
    secNode.text = p.src[headingStart..closeStart].strip;
    p.nodes ~= secNode;

    p.pos = lineEnd;
    p.skipNewlines();
    return true;
}

/// Unordered (* item) and ordered (# item) lists.
void parseList(ref WikitextParser p, NodeType listType, char marker)
{
    uint listIdx = cast(uint) p.nodes.length;
    p.nodes ~= Node(listType);
    uint firstChild = cast(uint) p.nodes.length;

    while (p.pos < p.src.length && p.atLineStart() && p.peek() == marker)
    {
        int depth = 0;
        while (p.pos + depth < p.src.length && p.src[p.pos + depth] == marker)
            depth++;
        p.pos += depth;

        size_t lineEnd = p.findLineEnd(p.pos);
        string content = p.src[p.pos..lineEnd].strip;
        p.pos = lineEnd;
        p.skipNewlines();

        Node itemNode = Node(NodeType.ListItem);
        itemNode.level = cast(ubyte) depth;

        uint itemIdx = cast(uint) p.nodes.length;
        p.nodes ~= itemNode;
        uint inlineStart = cast(uint) p.nodes.length;
        parseInlineInto(p, content);
        p.nodes[itemIdx].childStart = inlineStart;
        p.nodes[itemIdx].childEnd = cast(uint) p.nodes.length;
    }

    p.nodes[listIdx].childStart = firstChild;
    p.nodes[listIdx].childEnd = cast(uint) p.nodes.length;
}

/// Definition lists (; term and : description).
void parseDefinitionList(ref WikitextParser p)
{
    uint defListIdx = cast(uint) p.nodes.length;
    p.nodes ~= Node(NodeType.DefinitionList);
    uint firstChild = cast(uint) p.nodes.length;

    while (p.pos < p.src.length && p.atLineStart() && (p.peek() == ';' || p.peek() == ':'))
    {
        char marker = p.src[p.pos];
        p.pos++;
        size_t lineEnd = p.findLineEnd(p.pos);
        string content = p.src[p.pos..lineEnd].strip;
        p.pos = lineEnd;
        p.skipNewlines();

        NodeType nodeType = marker == ';' ? NodeType.DefinitionTerm : NodeType.DefinitionDesc;
        uint itemIdx = cast(uint) p.nodes.length;
        p.nodes ~= Node(nodeType);
        uint inlineStart = cast(uint) p.nodes.length;
        parseInlineInto(p, content);
        p.nodes[itemIdx].childStart = inlineStart;
        p.nodes[itemIdx].childEnd = cast(uint) p.nodes.length;
    }

    p.nodes[defListIdx].childStart = firstChild;
    p.nodes[defListIdx].childEnd = cast(uint) p.nodes.length;
}

/// Preformatted text (lines starting with a space).
void parsePreformatted(ref WikitextParser p)
{
    string content;
    while (p.pos < p.src.length && p.atLineStart() && p.peek() == ' ')
    {
        p.pos++;
        size_t lineEnd = p.findLineEnd(p.pos);
        if (content.length > 0)
            content = content~"\n"~p.src[p.pos..lineEnd];
        else
            content = p.src[p.pos..lineEnd];
        p.pos = lineEnd;
        if (p.pos < p.src.length && p.src[p.pos] == '\n')
            p.pos++;
    }

    if (content.length > 0)
    {
        uint paragraphIdx = cast(uint) p.nodes.length;
        p.nodes ~= Node(NodeType.Paragraph);
        uint childStart = cast(uint) p.nodes.length;
        parseInlineInto(p, content);
        p.nodes[paragraphIdx].childStart = childStart;
        p.nodes[paragraphIdx].childEnd = cast(uint) p.nodes.length;
    }
}

/// <nowiki>...</nowiki> and self-closing variants.
void parseNoWiki(ref WikitextParser p)
{
    if (p.matchAt("<nowiki/>"))
    {
        p.pos += 9;
        return;
    }
    if (p.matchAt("<nowiki />"))
    {
        p.pos += 10;
        return;
    }

    p.pos += 8;
    ptrdiff_t endIdx = p.src[p.pos..$].indexOf("</nowiki>");
    if (endIdx < 0)
    {
        p.nodes ~= Node(NodeType.NoWiki, p.src[p.pos..$]);
        p.pos = p.src.length;
    }
    else
    {
        size_t absEnd = p.pos + endIdx;
        p.nodes ~= Node(NodeType.NoWiki, p.src[p.pos..absEnd]);
        p.pos = absEnd + 9;
    }
}

/// <math>...</math> blocks.
void parseMathBlock(ref WikitextParser p)
{
    ptrdiff_t tagEnd = p.src[p.pos..$].indexOf('>');
    if (tagEnd < 0)
    {
        p.pos = p.src.length;
        return;
    }
    p.pos += tagEnd + 1;
    ptrdiff_t endIdx = p.src[p.pos..$].indexOf("</math>");
    if (endIdx < 0)
    {
        p.nodes ~= Node(NodeType.Math, p.src[p.pos..$]);
        p.pos = p.src.length;
    }
    else
    {
        size_t absEnd = p.pos + endIdx;
        p.nodes ~= Node(NodeType.Math, p.src[p.pos..absEnd]);
        p.pos = absEnd + 7;
    }
}

/// [[Category:Name|Sortkey]]
void parseCategory(ref WikitextParser p)
{
    p.pos += 2;
    ptrdiff_t close = p.src[p.pos..$].indexOf("]]");
    if (close < 0)
    {
        p.pos = p.src.length;
        return;
    }
    size_t absClose = p.pos + close;
    string inner = p.src[p.pos..absClose];

    ptrdiff_t colon = inner.indexOf(':');
    if (colon >= 0)
        inner = inner[colon + 1..$];

    ptrdiff_t pipeIdx = inner.indexOf('|');
    string name = pipeIdx >= 0 ? inner[0..pipeIdx] : inner;

    Node categoryNode = Node(NodeType.Category);
    categoryNode.text = name.strip;
    p.nodes ~= categoryNode;
    p.pos = absClose + 2;
    p.skipNewlines();
}

/// #REDIRECT [[Target]]
void parseRedirect(ref WikitextParser p)
{
    p.pos += 9;
    while (p.pos < p.src.length && p.src[p.pos] == ' ')
        p.pos++;
    ptrdiff_t close = p.src[p.pos..$].indexOf("]]");
    if (close < 0)
    {
        p.pos = p.src.length;
        return;
    }
    size_t absClose = p.pos + close;
    string target = p.src[p.pos..absClose];
    if (target.length >= 2 && target[0..2] == "[[")
        target = target[2..$];
    Node redirectNode = Node(NodeType.Redirect);
    redirectNode.target = target.strip;
    p.nodes ~= redirectNode;
    p.pos = absClose + 2;
}

/// Block-level <ref>...</ref> or self-closing <ref ... />.
bool tryParseBlockRef(ref WikitextParser p)
{
    ptrdiff_t tagEnd = p.src[p.pos..$].indexOf('>');
    if (tagEnd < 0)
        return false;
    size_t absTagEnd = p.pos + tagEnd;

    // Self-closing <ref ... />
    if (p.src[absTagEnd - 1] == '/'
        || (absTagEnd >= 2 && p.src[absTagEnd - 1] == ' ' && p.src[absTagEnd - 2] == '/'))
    {
        Node refNode = Node(NodeType.Reference);
        refNode.text = p.src[p.pos..absTagEnd + 1];
        p.nodes ~= refNode;
        p.pos = absTagEnd + 1;
        p.skipNewlines();
        return true;
    }

    // <ref>content</ref>
    ptrdiff_t endRef = p.src[absTagEnd + 1..$].indexOf("</ref>");
    if (endRef >= 0)
    {
        size_t contentStart = absTagEnd + 1;
        size_t absEndRef = contentStart + endRef;
        Node refNode = Node(NodeType.Reference);
        refNode.text = p.src[contentStart..absEndRef];
        p.nodes ~= refNode;
        p.pos = absEndRef + 6;
        p.skipNewlines();
        return true;
    }

    return false;
}

/// Paragraph: inline content until blank line or block element.
void parseParagraph(ref WikitextParser p)
{
    size_t start = p.pos;
    int refDepth = 0;

    while (p.pos < p.src.length)
    {
        if (p.pos + 5 < p.src.length && p.src[p.pos..p.pos + 4] == "<ref"
            && (p.src[p.pos + 4] == '>' || p.src[p.pos + 4] == ' '))
        {
            refDepth++;
        }
        if (p.pos + 6 <= p.src.length && p.src[p.pos..p.pos + 6] == "</ref>")
        {
            if (refDepth > 0)
                refDepth--;
            p.pos += 6;
            continue;
        }
        if (refDepth > 0 && p.src[p.pos] == '/' && p.pos + 1 < p.src.length
            && p.src[p.pos + 1] == '>')
        {
            refDepth--;
            p.pos += 2;
            continue;
        }

        if (refDepth <= 0)
        {
            // Double newline ends paragraph.
            if (p.pos + 1 < p.src.length && p.src[p.pos] == '\n'
                && p.src[p.pos + 1] == '\n')
                break;

            // Single newline followed by block-start character ends paragraph.
            if (p.src[p.pos] == '\n' && p.pos + 1 < p.src.length)
            {
                char next = p.src[p.pos + 1];
                if (next == '=' || next == '*' || next == '#'
                    || next == ';' || next == ':' || next == ' ')
                    break;
                if (p.pos + 2 < p.src.length
                    && (p.src[p.pos + 1..p.pos + 3] == "{|"
                        || p.src[p.pos + 1..p.pos + 3] == "|}"))
                    break;
                if (p.pos + 10 < p.src.length
                    && p.src[p.pos + 1..p.pos + 10] == "#REDIRECT")
                    break;
            }
        }
        p.pos++;
    }

    if (p.pos > start)
    {
        string content = p.src[start..p.pos].strip;
        if (content.length > 0)
        {
            uint paragraphIdx = cast(uint) p.nodes.length;
            p.nodes ~= Node(NodeType.Paragraph);
            uint childStart = cast(uint) p.nodes.length;
            parseInlineInto(p, content);
            p.nodes[paragraphIdx].childStart = childStart;
            p.nodes[paragraphIdx].childEnd = cast(uint) p.nodes.length;
        }
    }

    p.skipNewlines();
}

/// Parse inline wikitext content into AST nodes:
/// bold/italic, links, external links, templates, references,
/// HTML tags, line breaks, comments.
void parseInlineInto(ref WikitextParser p, string text)
{
    if (text.length == 0)
        return;

    size_t i = 0;
    size_t textStart = 0;

    void flushText()
    {
        if (i > textStart)
        {
            Node textNode = Node(NodeType.Text);
            textNode.text = text[textStart..i];
            p.nodes ~= textNode;
        }
    }

    while (i < text.length)
    {
        // HTML comment
        if (i + 4 < text.length && text[i..i + 4] == "<!--")
        {
            flushText();
            ptrdiff_t end = text[i + 4..$].indexOf("-->");
            if (end < 0)
            {
                p.nodes ~= Node(NodeType.Comment, text[i + 4..$]);
                textStart = text.length;
                i = text.length;
            }
            else
            {
                size_t absEnd = i + 4 + end;
                p.nodes ~= Node(NodeType.Comment, text[i + 4..absEnd]);
                i = absEnd + 3;
                textStart = i;
            }
            continue;
        }

        // Template {{ ... }}
        if (i + 1 < text.length && text[i] == '{' && text[i + 1] == '{')
        {
            flushText();
            ptrdiff_t end = findMatchingClose(text, i + 2, "{{", "}}");
            if (end < 0)
            {
                textStart = i;
                i = text.length;
            }
            else
            {
                Node templateNode = Node(NodeType.Template);
                templateNode.text = text[i + 2..end];
                p.nodes ~= templateNode;
                i = end + 2;
                textStart = i;
            }
            continue;
        }

        // Wikilink [[ ... ]]
        if (i + 1 < text.length && text[i] == '[' && text[i + 1] == '[')
        {
            flushText();
            ptrdiff_t close = findMatchingClose(text, i + 2, "[[", "]]");
            if (close < 0)
            {
                textStart = i;
                i += 2;
                continue;
            }

            string inner = text[i + 2..close];
            i = close + 2;
            textStart = i;

            // Category [[Category:...]]
            if (inner.length > 9
                && (inner[0..9] == "Category:" || inner[0..9] == "category:"))
            {
                Node categoryNode = Node(NodeType.Category);
                ptrdiff_t pipeIdx = inner[9..$].indexOf('|');
                categoryNode.text = pipeIdx >= 0
                    ? inner[9..9 + pipeIdx].strip
                    : inner[9..$].strip;
                p.nodes ~= categoryNode;
                continue;
            }

            // File/Image [[File:...]] [[Image:...]]
            if ((inner.length > 5
                    && (inner[0..5] == "File:" || inner[0..5] == "file:"))
                || (inner.length > 6
                    && (inner[0..6] == "Image:" || inner[0..6] == "image:")))
            {
                Node imageNode = Node(NodeType.Image);
                ptrdiff_t colon = inner.indexOf(':');
                imageNode.target = colon >= 0 ? inner[colon + 1..$] : inner;
                ptrdiff_t pipeIdx = inner.lastIndexOf('|');
                if (pipeIdx >= 0)
                    imageNode.text = inner[pipeIdx + 1..$].strip;
                p.nodes ~= imageNode;
                continue;
            }

            // Regular wikilink
            Node linkNode = Node(NodeType.Link);
            ptrdiff_t pipeIdx = inner.indexOf('|');
            if (pipeIdx >= 0)
            {
                linkNode.target = inner[0..pipeIdx].strip;
                linkNode.text = inner[pipeIdx + 1..$].strip;
            }
            else
            {
                linkNode.target = inner.strip;
                linkNode.text = inner.strip;
            }
            p.nodes ~= linkNode;
            continue;
        }

        // External link [url text]
        if (text[i] == '[' && (i + 1 >= text.length || text[i + 1] != '['))
        {
            if (i + 8 < text.length
                && (text[i + 1..i + 8] == "http://"
                    || (i + 9 < text.length && text[i + 1..i + 9] == "https://")))
            {
                flushText();
                ptrdiff_t close = text[i + 1..$].indexOf(']');
                if (close >= 0)
                {
                    size_t absClose = i + 1 + close;
                    string inner = text[i + 1..absClose];
                    ptrdiff_t spaceIdx = inner.indexOf(' ');
                    Node extLinkNode = Node(NodeType.ExtLink);
                    if (spaceIdx >= 0)
                    {
                        extLinkNode.target = inner[0..spaceIdx];
                        extLinkNode.text = inner[spaceIdx + 1..$].strip;
                    }
                    else
                    {
                        extLinkNode.target = inner;
                        extLinkNode.text = inner;
                    }
                    p.nodes ~= extLinkNode;
                    i = absClose + 1;
                    textStart = i;
                    continue;
                }
            }
        }

        // Bold/italic markup
        if (text[i] == '\'' && i + 1 < text.length && text[i + 1] == '\'')
        {
            flushText();

            int quoteCount = 0;
            size_t quoteStart = i;
            while (i < text.length && text[i] == '\'')
            {
                quoteCount++;
                i++;
            }

            NodeFlags styleFlags;
            if (quoteCount >= 5)
                styleFlags = cast(NodeFlags)(NodeFlags.Bold | NodeFlags.Italic);
            else if (quoteCount >= 3)
                styleFlags = NodeFlags.Bold;
            else
                styleFlags = NodeFlags.Italic;

            int closeQuotes = quoteCount >= 5 ? 5 : quoteCount >= 3 ? 3 : 2;
            string closeStr = closeQuotes == 5 ? "'''''" : closeQuotes == 3 ? "'''" : "''";

            ptrdiff_t closeIdx = text[i..$].indexOf(closeStr);
            if (closeIdx < 0)
            {
                // No matching close — emit quotes as plain text.
                Node textNode = Node(NodeType.Text);
                textNode.text = text[quoteStart..i];
                p.nodes ~= textNode;
                textStart = i;
                continue;
            }

            size_t absClose = i + closeIdx;
            uint styledIdx = cast(uint) p.nodes.length;
            Node styledNode = Node(NodeType.Styled);
            styledNode.flags = styleFlags;
            p.nodes ~= styledNode;
            uint childStart = cast(uint) p.nodes.length;
            parseInlineInto(p, text[i..absClose]);
            p.nodes[styledIdx].childStart = childStart;
            p.nodes[styledIdx].childEnd = cast(uint) p.nodes.length;

            i = absClose + closeStr.length;
            textStart = i;
            continue;
        }

        // <ref>...</ref> (inline reference)
        if (i + 4 < text.length && text[i..i + 4] == "<ref")
        {
            flushText();
            ptrdiff_t tagEnd = text[i..$].indexOf('>');
            if (tagEnd >= 0)
            {
                size_t absTagEnd = i + tagEnd;

                // Self-closing <ref ... />
                if (text[absTagEnd - 1] == '/'
                    || (tagEnd >= 2 && text[absTagEnd - 1] == ' '
                        && text[absTagEnd - 2] == '/'))
                {
                    Node refNode = Node(NodeType.Reference);
                    refNode.text = text[i..absTagEnd + 1];
                    p.nodes ~= refNode;
                    i = absTagEnd + 1;
                    textStart = i;
                    continue;
                }

                // <ref>content</ref>
                size_t contentStart = absTagEnd + 1;
                ptrdiff_t endRef = text[contentStart..$].indexOf("</ref>");
                if (endRef >= 0)
                {
                    size_t absEndRef = contentStart + endRef;
                    Node refNode = Node(NodeType.Reference);
                    refNode.text = text[contentStart..absEndRef];
                    p.nodes ~= refNode;
                    i = absEndRef + 6;
                    textStart = i;
                    continue;
                }
            }
            // Couldn't parse ref, skip the '<'.
            i++;
            continue;
        }

        // <br>, <br/>, <br />
        if (i + 3 < text.length && text[i..i + 3] == "<br")
        {
            flushText();
            ptrdiff_t tagEnd = text[i..$].indexOf('>');
            if (tagEnd >= 0)
            {
                p.nodes ~= Node(NodeType.LineBreak);
                i += tagEnd + 1;
                textStart = i;
                continue;
            }
        }

        // Generic HTML tags (inline opening)
        if (text[i] == '<' && i + 1 < text.length)
        {
            import std.ascii : isAlpha;
            if (isAlpha(text[i + 1]) || text[i + 1] == '/')
            {
                flushText();
                ptrdiff_t tagEnd = text[i..$].indexOf('>');
                if (tagEnd >= 0)
                {
                    size_t absTagEnd = i + tagEnd;
                    Node htmlTagNode = Node(NodeType.HtmlTag);
                    htmlTagNode.text = text[i..absTagEnd + 1];
                    p.nodes ~= htmlTagNode;
                    i = absTagEnd + 1;
                    textStart = i;
                    continue;
                }
            }
        }

        i++;
    }

    // Flush remaining text.
    if (textStart < text.length)
    {
        Node textNode = Node(NodeType.Text);
        textNode.text = text[textStart..$];
        p.nodes ~= textNode;
    }
}
