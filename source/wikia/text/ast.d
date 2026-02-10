module wikia.text.ast;

/// Unified AST for both Wikitext and XML document formats.
/// Memory-efficient: nodes use slices into the original source string
/// wherever possible, avoiding copies. Children are stored as slices
/// of a flat array owned by the Document.

enum NodeType : ubyte
{
    // Structural
    Document,
    Section,
    Paragraph,

    // Inline
    Text,
    Bold,
    Italic,
    BoldItalic,
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

struct Node
{
    NodeType type;

    /// Slice into original source (zero-copy for text content).
    const(char)[] text;

    /// For Section: heading level (2-6). For ListItem: nesting depth.
    ubyte level;

    /// For Link/ExtLink: target URL or page name.
    const(char)[] target;

    /// Child node range: indices into Document.nodes.
    uint childStart;
    uint childEnd;

    Node[] children(return ref const(Node)[] allNodes) return
    {
        if (childStart >= childEnd)
            return [];
        return cast(Node[]) allNodes[childStart..childEnd];
    }

    bool hasChildren() const pure nothrow @nogc
    {
        return childEnd > childStart;
    }

    uint childCount() const pure nothrow @nogc
    {
        return childEnd - childStart;
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
    /// In the flat array, childStart..childEnd spans all descendants.
    uint nextSiblingIdx(uint i) const pure nothrow @nogc
    {
        return nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
    }

    /// Recursively extract visible plain text from a node subtree.
    /// Skips templates, comments, references, categories, images, etc.
    string extractText(ref const Node node)
    {
        // Skip non-visible node types entirely.
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
            return cast(string) node.text;

        // For Link/ExtLink: return display text.
        if (node.type == NodeType.Link || node.type == NodeType.ExtLink)
        {
            if (node.text.length > 0)
                return cast(string) node.text;
            if (node.target.length > 0)
                return cast(string) node.target;
            return "";
        }

        if (node.type == NodeType.LineBreak)
            return "\n";

        if (node.type == NodeType.HorizontalRule)
            return "\n";

        if (!node.hasChildren)
        {
            if (node.type == NodeType.Preformatted || node.type == NodeType.Section)
                return node.text.length > 0 ? cast(string) node.text : "";
            return "";
        }

        string result;
        uint i = node.childStart;
        while (i < node.childEnd)
        {
            result ~= extractText(nodes[i]);
            i = nextSiblingIdx(i);
        }
        return result;
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
        string result;
        foreach (ref n; preamble())
            result ~= extractText(n);
        return result;
    }

    /// Drop all nodes of the specified types (and their subtrees)
    /// from the document, rebuilding the flat array in-place.
    /// `flags` is a bitmask of NodeType values to drop.
    void drop(uint flags)
    {
        if (nodes.length <= 1)
            return;

        Node[] result;
        result.reserve(nodes.length);
        result ~= Node(NodeType.Document); // root

        // Recursively copy, skipping dropped types.
        void copyChildren(uint start, uint end, uint parentIdx)
        {
            uint newChildStart = cast(uint) result.length;
            uint i = start;
            while (i < end)
            {
                if ((1u << nodes[i].type) & flags)
                {
                    // Skip this node and its subtree.
                    i = nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
                    continue;
                }

                uint newIdx = cast(uint) result.length;
                result ~= nodes[i];

                if (nodes[i].hasChildren)
                {
                    copyChildren(nodes[i].childStart, nodes[i].childEnd, newIdx);
                }
                else
                {
                    result[newIdx].childStart = 0;
                    result[newIdx].childEnd = 0;
                }

                i = nodes[i].hasChildren ? nodes[i].childEnd : i + 1;
            }

            result[parentIdx].childStart = newChildStart;
            result[parentIdx].childEnd = cast(uint) result.length;
        }

        copyChildren(nodes[0].childStart, nodes[0].childEnd, 0);
        nodes = result;
    }

    /// Helper: build a drop-flags bitmask from NodeType values.
    static uint dropFlag(NodeType[] types...)
    {
        uint flags = 0;
        foreach (t; types)
            flags |= (1u << t);
        return flags;
    }
}
