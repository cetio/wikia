module wikia.text.ast;

/// Unified AST for both Wikitext and XML document formats.
/// Memory-efficient: nodes use slices into the original source string
/// wherever possible, avoiding copies. Children are stored as index
/// ranges into a flat array owned by the Document.

enum NodeType : ubyte
{
    // Structural
    Document,
    Section,
    Paragraph,

    // Inline
    Text,
    Styled,
    Link,
    ExtLink,
    Image,
    Template,
    HtmlTag,
    LineBreak,

    // Block
    UnorderedList,
    OrderedList,
    ListItem,
    DefinitionList,
    DefinitionTerm,
    DefinitionDesc,
    Table,
    TableRow,
    TableHeader,
    TableCell,
    TableCaption,
    Preformatted,
    HorizontalRule,
    BlockQuote,
    Reference,
    Category,
    Redirect,
    Comment,
    NoWiki,
    Math,
}

/// Bitflags for node modifiers. Applied to `Styled` nodes and
/// potentially others. Combined freely: `Bold | Italic`.
enum NodeFlags : ubyte
{
    None    = 0,
    Bold    = 1 << 0,
    Italic  = 1 << 1,
}

struct Node
{
    NodeType type;

    /// Slice into original source (zero-copy for text content).
    string text;

    NodeFlags flags;

    /// For Section: heading level (2-6). For ListItem: nesting depth.
    ubyte level;

    /// For Link/ExtLink: target URL or page name.
    string target;

    /// Child node range: indices into Document.nodes.
    uint childStart;
    uint childEnd;

    Node[] children(return ref Node[] allNodes) return
    {
        if (childStart >= childEnd)
            return [];
        return allNodes[childStart..childEnd];
    }

    bool hasChildren() const pure nothrow @nogc
    {
        return childEnd > childStart;
    }

    uint childCount() const pure nothrow @nogc
    {
        return childEnd - childStart;
    }

    bool hasFlag(NodeFlags f) const pure nothrow @nogc
    {
        return (flags & f) != NodeFlags.None;
    }
}

struct Document
{
    /// Flat storage for all AST nodes. The first node (index 0) is
    /// always the root Document node.
    Node[] nodes;

    /// The original source text, kept alive so slices remain valid.
    string source;

    /// Root document node.
    ref inout(Node) root() inout return
    {
        return nodes[0];
    }

    /// Advance past a node's subtree to find the next sibling index.
    uint nextSiblingIdx(uint i) const pure nothrow @nogc
    {
        return nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
    }

    /// Recursively extract visible plain text from a node subtree.
    string extractText(ref const Node node)
    {
        switch (node.type) with (NodeType)
        {
            case Template:
            case Comment:
            case Reference:
            case Category:
            case Image:
            case Redirect:
            case Math:
            case HtmlTag:
                return "";
            default:
                break;
        }

        if (node.type == NodeType.Text || node.type == NodeType.NoWiki)
            return node.text;

        if (node.type == NodeType.Link || node.type == NodeType.ExtLink)
        {
            if (node.text.length > 0)
                return node.text;
            if (node.target.length > 0)
                return node.target;
            return "";
        }

        if (node.type == NodeType.LineBreak)
            return "\n";

        if (node.type == NodeType.HorizontalRule)
            return "\n";

        if (!node.hasChildren)
        {
            if (node.type == NodeType.Preformatted || node.type == NodeType.Section)
                return node.text.length > 0 ? node.text : "";
            return "";
        }

        string ret;
        uint i = node.childStart;
        while (i < node.childEnd)
        {
            ret ~= extractText(nodes[i]);
            i = nextSiblingIdx(i);
        }
        return ret;
    }

    /// Get top-level sections (direct children of root with type Section).
    Node[] sections()
    {
        if (nodes.length == 0)
            return [];
        Node[] ret;
        uint i = nodes[0].childStart;
        while (i < nodes[0].childEnd)
        {
            if (nodes[i].type == NodeType.Section)
                ret ~= nodes[i];
            i = nextSiblingIdx(i);
        }
        return ret;
    }

    /// Get the preamble: all root children before the first Section.
    Node[] preamble()
    {
        if (nodes.length == 0)
            return [];
        Node[] ret;
        uint i = nodes[0].childStart;
        while (i < nodes[0].childEnd)
        {
            if (nodes[i].type == NodeType.Section)
                break;
            ret ~= nodes[i];
            i = nextSiblingIdx(i);
        }
        return ret;
    }

    /// Extract plain text from the preamble nodes.
    string preambleText()
    {
        string ret;
        foreach (ref n; preamble())
            ret ~= extractText(n);
        return ret;
    }

    /// Drop all nodes of the specified types (and their subtrees)
    /// from the document, rebuilding the flat array in-place.
    void drop(uint flags)
    {
        if (nodes.length <= 1)
            return;

        Node[] ret;
        ret.reserve(nodes.length);
        ret ~= Node(NodeType.Document);

        void copyChildren(uint start, uint end, uint parentIdx)
        {
            uint newChildStart = cast(uint) ret.length;
            bool preserve = ret[parentIdx].type == NodeType.TableCell
                         || ret[parentIdx].type == NodeType.TableHeader
                         || ret[parentIdx].type == NodeType.TableCaption;
            uint i = start;
            while (i < end)
            {
                if (!preserve && (1u << nodes[i].type) & flags)
                {
                    i = nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
                    continue;
                }

                uint newIdx = cast(uint) ret.length;
                ret ~= nodes[i];

                if (nodes[i].hasChildren)
                {
                    copyChildren(nodes[i].childStart, nodes[i].childEnd, newIdx);
                }
                else
                {
                    ret[newIdx].childStart = 0;
                    ret[newIdx].childEnd = 0;
                }

                i = nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
            }

            ret[parentIdx].childStart = newChildStart;
            ret[parentIdx].childEnd = cast(uint) ret.length;
        }

        copyChildren(nodes[0].childStart, nodes[0].childEnd, 0);
        nodes = ret;
    }

    static uint dropFlag(NodeType[] types...)
    {
        uint flags = 0;
        foreach (t; types)
            flags |= (1u << t);
        return flags;
    }
}
