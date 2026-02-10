module wikia.text.wiki;

import std.string : indexOf, strip;

import wikia.text.ast;
import wikia.text.utils : findMatchingClose;

public import wikia.text.wiki.semantic;
public import wikia.text.wiki.didactic;

/// Parse wikitext source into a Document AST.
Document parseWikitext(string src)
{
    WikitextParser parser = WikitextParser(src);
    parser.parse();
    return Document(parser.nodes, src);
}

package struct WikitextParser
{
    string src;
    size_t pos;
    Node[] nodes;

    this(string src)
    {
        this.src = src;
        this.pos = 0;
        nodes.reserve(512);
    }

    void parse()
    {
        nodes ~= Node(NodeType.Document);
        parseBody();
        nodes[0].childStart = 1;
        nodes[0].childEnd = cast(uint) nodes.length;
        restructure();
    }
    
    char peek() const pure nothrow @nogc
        => src[pos];

    size_t remaining() const pure nothrow @nogc
        => src.length - pos;

    bool matchAt(string str) const pure nothrow @nogc
        => pos + str.length <= src.length && src[pos..pos + str.length] == str;

    bool atLineStart() const pure nothrow @nogc
        => pos == 0 || src[pos - 1] == '\n';

    size_t findLineEnd(size_t from) const pure nothrow @nogc
    {
        size_t cur = from;
        while (cur < src.length && src[cur] != '\n')
            cur++;
        return cur;
    }

    // --- Top-level block dispatch ---

    void parseBody()
    {
        while (pos < src.length)
        {
            skipComments();
            if (pos >= src.length)
                break;

            if (atLineStart() && peek() == '=')
            {
                if (tryParseHeading(this))
                    continue;
            }

            if (pos + 9 < src.length && src[pos..pos + 9] == "#REDIRECT")
            {
                parseRedirect(this);
                continue;
            }

            if (atLineStart() && remaining() >= 4 && src[pos..pos + 4] == "----")
            {
                parseHorizontalRule(this);
                continue;
            }

            if (atLineStart() && peek() == '*')
            {
                parseList(this, NodeType.UnorderedList, '*');
                continue;
            }

            if (atLineStart() && peek() == '#')
            {
                parseList(this, NodeType.OrderedList, '#');
                continue;
            }

            if (atLineStart() && (peek() == ';' || peek() == ':'))
            {
                parseDefinitionList(this);
                continue;
            }

            if (atLineStart() && remaining() >= 2 && src[pos..pos + 2] == "{|")
            {
                parseTable(this);
                continue;
            }

            if (atLineStart() && peek() == ' ')
            {
                parsePreformatted(this);
                continue;
            }

            if (matchAt("<nowiki>") || matchAt("<nowiki/>") || matchAt("<nowiki />"))
            {
                parseNoWiki(this);
                continue;
            }

            if (matchAt("<math>") || matchAt("<math "))
            {
                parseMathBlock(this);
                continue;
            }

            if (matchAt("<blockquote>") || matchAt("<blockquote "))
            {
                parseHtmlBlock(this, "blockquote", NodeType.BlockQuote);
                continue;
            }

            if (matchAt("[[Category:") || matchAt("[[category:"))
            {
                parseCategory(this);
                continue;
            }

            if (remaining() >= 2 && src[pos..pos + 2] == "{{")
            {
                ptrdiff_t closePos = findMatchingClose(src, pos + 2, "{{", "}}");
                if (closePos >= 0)
                {
                    Node templateNode = Node(NodeType.Template);
                    templateNode.text = src[pos + 2..closePos];
                    nodes ~= templateNode;
                    pos = closePos + 2;
                    skipNewlines();
                    continue;
                }
            }

            if (matchAt("<ref"))
            {
                if (tryParseBlockRef(this))
                    continue;
            }

            parseParagraph(this);
        }
    }

    // --- Restructuring pass ---
    // After flat parsing, sections only have heading text but no children.
    // Restructure so each Section node owns all subsequent content until
    // the next section of same or higher level.

    void restructure()
    {
        if (nodes.length <= 1)
            return;

        Node[] ret;
        ret.reserve(nodes.length);
        ret ~= Node(NodeType.Document);

        uint[] topChildren;
        uint i = 1;
        while (i < cast(uint) nodes.length)
        {
            topChildren ~= i;
            if (nodes[i].hasChildren)
                i = nodes[i].childEnd;
            else
                i++;
        }

        rebuildSections(ret, topChildren);
        ret[0].childStart = 1;
        ret[0].childEnd = cast(uint) ret.length;
        nodes = ret;
    }

    void rebuildSections(ref Node[] ret, uint[] indices)
    {
        size_t i = 0;
        while (i < indices.length)
        {
            uint idx = indices[i];

            if (nodes[idx].type != NodeType.Section)
            {
                deepCopy(ret, idx);
                i++;
                continue;
            }

            ubyte secLevel = nodes[idx].level;
            uint secIdx = cast(uint) ret.length;
            ret ~= nodes[idx];

            uint childStart = cast(uint) ret.length;
            i++;

            uint[] bodyIndices;
            while (i < indices.length)
            {
                uint bodyIdx = indices[i];
                if (nodes[bodyIdx].type == NodeType.Section
                    && nodes[bodyIdx].level <= secLevel)
                    break;
                bodyIndices ~= bodyIdx;
                i++;
            }

            rebuildSections(ret, bodyIndices);
            ret[secIdx].childStart = childStart;
            ret[secIdx].childEnd = cast(uint) ret.length;
        }
    }

    void deepCopy(ref Node[] ret, uint idx)
    {
        uint newIdx = cast(uint) ret.length;
        Node node = nodes[idx];
        ret ~= node;

        if (node.hasChildren)
        {
            uint newChildStart = cast(uint) ret.length;
            uint cur = node.childStart;
            while (cur < node.childEnd)
            {
                deepCopy(ret, cur);
                if (nodes[cur].hasChildren)
                    cur = nodes[cur].childEnd;
                else
                    cur++;
            }
            ret[newIdx].childStart = newChildStart;
            ret[newIdx].childEnd = cast(uint) ret.length;
        }
    }

    void skipNewlines()
    {
        while (pos < src.length && (src[pos] == '\n' || src[pos] == '\r'))
            pos++;
    }

    void skipComments()
    {
        while (pos + 4 < src.length && src[pos..pos + 4] == "<!--")
        {
            ptrdiff_t end = src[pos + 4..$].indexOf("-->");
            if (end < 0)
            {
                nodes ~= Node(NodeType.Comment, src[pos + 4..$]);
                pos = src.length;
                return;
            }
            size_t absEnd = pos + 4 + end;
            nodes ~= Node(NodeType.Comment, src[pos + 4..absEnd]);
            pos = absEnd + 3;
            skipNewlines();
        }
    }
}
