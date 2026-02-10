module gui.article.render;

import gtk.box;
import gtk.label;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

import wikia.text.ast;
import wikia.page : Page;

/// Render a Page's AST into GTK widgets appended to `container`.
/// Skips References, Comments, Categories, Templates, Images.
void renderPage(Page page, Box container)
{
    if (page is null) return;
    auto doc = page.document();
    if (doc.nodes.length == 0) return;

    // Render preamble nodes.
    foreach (ref n; doc.preamble())
        renderNode(doc, n, container);

    // Render top-level sections.
    foreach (ref n; doc.sections())
        renderSection(doc, n, container, null);
}

/// Render preamble nodes only (everything before first section).
void renderPreamble(Page page, Box container)
{
    if (page is null) return;
    auto doc = page.document();
    if (doc.nodes.length == 0) return;

    foreach (ref n; doc.preamble())
        renderNode(doc, n, container);
}

/// Render section content into a container. If `headingCallback` is
/// provided, it is called with the heading text and level instead of
/// creating a default heading label.
void renderSection(
    ref Document doc,
    ref const Node sec,
    Box container,
    void delegate(string heading, int level) headingCallback
)
{
    if (sec.type != NodeType.Section) return;

    // Heading.
    string heading = cast(string) sec.text;
    if (heading.length > 0)
    {
        if (headingCallback !is null)
            headingCallback(heading, sec.level);
        else
        {
            Label h = new Label(heading);
            h.addCssClass(sec.level <= 2 ? "article-heading" : "article-subheading");
            h.halign = Align.Start;
            h.xalign = 0;
            h.wrap = true;
            h.hexpand = true;
            container.append(h);
        }
    }

    // Section body.
    if (sec.hasChildren)
    {
        uint ci = sec.childStart;
        while (ci < sec.childEnd)
        {
            if (doc.nodes[ci].type == NodeType.Section)
                renderSection(doc, doc.nodes[ci], container, headingCallback);
            else
                renderNode(doc, doc.nodes[ci], container);
            ci = doc.nextSiblingIdx(ci);
        }
    }
}

/// Extract Pango markup from an inline node subtree. Used for
/// labels that support markup (bold, italic, links).
string nodeToMarkup(ref Document doc, ref const Node node)
{
    final switch (node.type) with (NodeType)
    {
        case Text:
            return escapeMarkup(cast(string) node.text);

        case Bold:
            return "<b>" ~ childrenMarkup(doc, node) ~ "</b>";

        case Italic:
            return "<i>" ~ childrenMarkup(doc, node) ~ "</i>";

        case BoldItalic:
            return "<b><i>" ~ childrenMarkup(doc, node) ~ "</i></b>";

        case Link:
            string display = node.text.length > 0
                ? escapeMarkup(cast(string) node.text)
                : escapeMarkup(cast(string) node.target);
            return display;

        case ExtLink:
            string display = node.text.length > 0
                ? escapeMarkup(cast(string) node.text)
                : escapeMarkup(cast(string) node.target);
            string target = cast(string) node.target;
            return `<a href="` ~ escapeMarkup(target) ~ `">` ~ display ~ `</a>`;

        case LineBreak:
            return "\n";

        case NoWiki:
            return escapeMarkup(cast(string) node.text);

        case Template:
        case Reference:
        case Comment:
        case Category:
        case Image:
        case Redirect:
        case HtmlTag:
        case Math:
            return "";

        case Paragraph:
        case Section:
        case Document:
        case UnorderedList:
        case OrderedList:
        case ListItem:
        case DefinitionList:
        case DefinitionTerm:
        case DefinitionDesc:
        case Table:
        case TableRow:
        case TableHeader:
        case TableCell:
        case TableCaption:
        case Preformatted:
        case HorizontalRule:
        case BlockQuote:
            return childrenMarkup(doc, node);
    }
}

/// Render a single AST node into GTK widgets.
void renderNode(ref Document doc, ref const Node node, Box container)
{
    final switch (node.type) with (NodeType)
    {
        case Paragraph:
            string markup = childrenMarkup(doc, node);
            if (markup.length > 0)
            {
                Label lbl = makeLabel(markup, true);
                container.append(lbl);
            }
            break;

        case Text:
            if (node.text.length > 0)
            {
                Label lbl = makeLabel(escapeMarkup(cast(string) node.text), false);
                container.append(lbl);
            }
            break;

        case Bold:
        case Italic:
        case BoldItalic:
        case Link:
        case ExtLink:
        case NoWiki:
            string markup = nodeToMarkup(doc, node);
            if (markup.length > 0)
            {
                Label lbl = makeLabel(markup, true);
                container.append(lbl);
            }
            break;

        case UnorderedList:
        case OrderedList:
            renderList(doc, node, container);
            break;

        case DefinitionList:
            renderDefinitionList(doc, node, container);
            break;

        case Table:
            renderTable(doc, node, container);
            break;

        case Preformatted:
            Label pre = new Label(cast(string) node.text);
            pre.addCssClass("article-preformatted");
            pre.halign = Align.Start;
            pre.xalign = 0;
            pre.wrap = false;
            pre.hexpand = true;
            pre.selectable = true;
            container.append(pre);
            break;

        case HorizontalRule:
            auto sep = new Box(Orientation.Horizontal, 0);
            sep.addCssClass("article-hr");
            sep.hexpand = true;
            sep.heightRequest = 1;
            container.append(sep);
            break;

        case BlockQuote:
            auto bq = new Box(Orientation.Vertical, 0);
            bq.addCssClass("article-blockquote");
            bq.hexpand = true;
            bq.marginStart = 24;
            if (node.hasChildren)
            {
                uint bi = node.childStart;
                while (bi < node.childEnd)
                {
                    renderNode(doc, doc.nodes[bi], bq);
                    bi = doc.nextSiblingIdx(bi);
                }
            }
            container.append(bq);
            break;

        case Section:
            // Sections handled separately via renderSection.
            break;

        case LineBreak:
            break;

        // Skip non-visual / inline-only nodes.
        case Reference:
        case Template:
        case Comment:
        case Category:
        case Image:
        case Redirect:
        case HtmlTag:
        case Math:
        case Document:
        case ListItem:
        case DefinitionTerm:
        case DefinitionDesc:
        case TableRow:
        case TableHeader:
        case TableCell:
        case TableCaption:
            break;
    }
}

private:

void renderList(ref Document doc, ref const Node list, Box container)
{
    if (!list.hasChildren) return;

    Box listBox = new Box(Orientation.Vertical, 2);
    listBox.addCssClass("article-list");
    listBox.hexpand = true;
    listBox.marginStart = 16;

    bool ordered = list.type == NodeType.OrderedList;
    int idx = 1;

    uint li = list.childStart;
    while (li < list.childEnd)
    {
        if (doc.nodes[li].type == NodeType.ListItem)
        {
            string bullet = "\u2022 ";
            if (ordered)
            {
                import std.conv : to;
                bullet = idx.to!string ~ ". ";
                idx++;
            }

            string content = childrenMarkup(doc, doc.nodes[li]);
            if (content.length == 0)
            {
                li = doc.nextSiblingIdx(li);
                continue;
            }
            string markup = bullet ~ content;
            Label lbl = makeLabel(markup, true);
            lbl.marginStart = cast(int)(
                doc.nodes[li].level > 1
                    ? (doc.nodes[li].level - 1) * 12 : 0);
            listBox.append(lbl);
        }
        li = doc.nextSiblingIdx(li);
    }

    container.append(listBox);
}

void renderDefinitionList(ref Document doc, ref const Node dl, Box container)
{
    if (!dl.hasChildren) return;

    Box dlBox = new Box(Orientation.Vertical, 2);
    dlBox.addCssClass("article-list");
    dlBox.hexpand = true;
    dlBox.marginStart = 16;

    uint di = dl.childStart;
    while (di < dl.childEnd)
    {
        string markup = childrenMarkup(doc, doc.nodes[di]);
        if (doc.nodes[di].type == NodeType.DefinitionTerm)
        {
            Label lbl = makeLabel("<b>" ~ markup ~ "</b>", true);
            dlBox.append(lbl);
        }
        else if (doc.nodes[di].type == NodeType.DefinitionDesc)
        {
            Label lbl = makeLabel(markup, true);
            lbl.marginStart = 12;
            dlBox.append(lbl);
        }
        di = doc.nextSiblingIdx(di);
    }

    container.append(dlBox);
}

void renderTable(ref Document doc, ref const Node table, Box container)
{
    // Render tables as a simple vertical layout of rows.
    if (!table.hasChildren) return;

    Box tableBox = new Box(Orientation.Vertical, 2);
    tableBox.addCssClass("article-table");
    tableBox.hexpand = true;

    uint ti = table.childStart;
    while (ti < table.childEnd)
    {
        if (doc.nodes[ti].type == NodeType.TableCaption)
        {
            Label cap = new Label(cast(string) doc.nodes[ti].text);
            cap.addCssClass("article-table-caption");
            cap.halign = Align.Start;
            cap.xalign = 0;
            cap.wrap = true;
            tableBox.append(cap);
            ti = doc.nextSiblingIdx(ti);
            continue;
        }

        if (doc.nodes[ti].type != NodeType.TableRow || !doc.nodes[ti].hasChildren)
        {
            ti = doc.nextSiblingIdx(ti);
            continue;
        }

        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("article-table-row");
        rowBox.hexpand = true;

        uint ri = doc.nodes[ti].childStart;
        while (ri < doc.nodes[ti].childEnd)
        {
            if (doc.nodes[ri].type == NodeType.TableCell
                || doc.nodes[ri].type == NodeType.TableHeader)
            {
                string markup = childrenMarkup(doc, doc.nodes[ri]);
                Label lbl = makeLabel(markup, true);
                if (doc.nodes[ri].type == NodeType.TableHeader)
                    lbl.addCssClass("article-table-header");
                lbl.hexpand = true;
                rowBox.append(lbl);
            }
            ri = doc.nextSiblingIdx(ri);
        }

        tableBox.append(rowBox);
        ti = doc.nextSiblingIdx(ti);
    }

    container.append(tableBox);
}

string childrenMarkup(ref Document doc, ref const Node parent)
{
    if (!parent.hasChildren)
    {
        if (parent.text.length > 0)
            return escapeMarkup(cast(string) parent.text);
        return "";
    }

    string result;
    uint ci = parent.childStart;
    while (ci < parent.childEnd)
    {
        result ~= nodeToMarkup(doc, doc.nodes[ci]);
        ci = doc.nextSiblingIdx(ci);
    }
    return result;
}

Label makeLabel(string text, bool markup)
{
    Label lbl = new Label(text);
    lbl.addCssClass("report-body-text");
    lbl.halign = Align.Start;
    lbl.xalign = 0;
    lbl.wrap = true;
    lbl.hexpand = true;
    lbl.selectable = true;
    if (markup)
        lbl.useMarkup = true;
    return lbl;
}

string refLabel(ref const Node node)
{
    if (node.text.length == 0)
        return "*";

    // Try to extract name="..." from the ref tag text.
    import std.string : indexOf;
    string t = cast(string) node.text;
    auto nameIdx = indexOf(t, `name="`);
    if (nameIdx >= 0)
    {
        size_t start = nameIdx + 6;
        auto endIdx = indexOf(t[start .. $], `"`);
        if (endIdx >= 0 && endIdx > 0)
            return escapeMarkup(t[start .. start + endIdx]);
    }
    return "*";
}

string escapeMarkup(string text)
{
    if (text is null || text.length == 0)
        return "";

    // Check if any escaping needed.
    bool needsEscape = false;
    foreach (c; text)
    {
        if (c == '&' || c == '<' || c == '>')
        {
            needsEscape = true;
            break;
        }
    }
    if (!needsEscape) return text;

    string result;
    result.reserve(text.length + 32);
    foreach (c; text)
    {
        switch (c)
        {
            case '&': result ~= "&amp;"; break;
            case '<': result ~= "&lt;"; break;
            case '>': result ~= "&gt;"; break;
            default: result ~= c; break;
        }
    }
    return result;
}
