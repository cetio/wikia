module gui.home;

import std.stdio : writeln;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.search_entry;
import gtk.list_box;
import gtk.list_box_row;
import gtk.overlay;
import gtk.types : Orientation, Align;

import gui.background : Background;
import wikia.pubchem;

class Homepage : Box
{
    private SearchEntry searchEntry;
    private ListBox suggestionList;

    void delegate(string query) onSearch;
    void delegate(int index) onResultSelected;

    this()
    {
        super(Orientation.Vertical, 0);
        writeln("[Homepage] Constructor started");
        
        Overlay overlay = new Overlay();
        overlay.hexpand = true;
        overlay.vexpand = true;

        Background bg = new Background();
        bg.hexpand = true;
        bg.vexpand = true;
        bg.addCssClass("homepage-background");
        overlay.setChild(bg);

        Box centeringBox = new Box(Orientation.Vertical, 0);
        centeringBox.hexpand = true;
        centeringBox.vexpand = true;
        centeringBox.halign = Align.Center;
        centeringBox.valign = Align.Center;

        Box content = buildContent();
        centeringBox.append(content);
        overlay.addOverlay(centeringBox);
        
        append(overlay);
        writeln("[Homepage] Constructor completed");
    }

    private Box buildContent()
    {
        Box content = new Box(Orientation.Vertical, 0);
        content.addCssClass("homepage-content");
        content.hexpand = false;
        content.halign = Align.Center;
        content.valign = Align.Start;

        content.append(buildLogo());
        content.append(buildTagline());
        content.append(buildSearch());
        
        suggestionList = new ListBox();
        suggestionList.addCssClass("search-results-container");
        suggestionList.connectRowActivated(&onRowActivated);
        suggestionList.visible = false;
        content.append(suggestionList);
        
        content.append(buildLinks());

        return content;
    }

    private Box buildLogo()
    {
        Box logoBox = new Box(Orientation.Horizontal, 0);
        logoBox.halign = Align.Center;

        Label logoW = new Label("Wik");
        logoW.addCssClass("homepage-logo");

        Label logoI = new Label("ia");
        logoI.addCssClass("homepage-logo");
        logoI.addCssClass("homepage-logo-accent");

        logoBox.append(logoW);
        logoBox.append(logoI);
        return logoBox;
    }

    private Label buildTagline()
    {
        Label tagline = new Label("The free chemical compound database");
        tagline.addCssClass("homepage-tagline");
        tagline.halign = Align.Center;
        return tagline;
    }

    private Box buildSearch()
    {
        Box searchBox = new Box(Orientation.Horizontal, 0);
        searchBox.addCssClass("homepage-search-box");
        searchBox.halign = Align.Center;
        searchBox.widthRequest = 600;

        searchEntry = new SearchEntry();
        searchEntry.placeholderText = "Search for a compound...";
        searchEntry.addCssClass("homepage-search-entry");
        searchEntry.hexpand = true;
        searchEntry.halign = Align.Fill;
        searchEntry.connectActivate(&onSearchActivated);
        searchBox.append(searchEntry);

        Button searchBtn = new Button();
        searchBtn.label = "Search";
        searchBtn.addCssClass("homepage-search-button");
        searchBtn.connectClicked(&onSearchBtnClicked);
        searchBox.append(searchBtn);

        return searchBox;
    }

    private Box buildLinks()
    {
        Box linksBox = new Box(Orientation.Horizontal, 16);
        linksBox.addCssClass("homepage-links");
        linksBox.halign = Align.Center;
        linksBox.marginTop = 24;

        Label linkText = new Label("Powered by");
        Label pubchemLink = new Label("PubChem");
        pubchemLink.addCssClass("homepage-link");

        linksBox.append(linkText);
        linksBox.append(pubchemLink);
        return linksBox;
    }

    @property SearchEntry getSearchEntry()
    {
        return searchEntry;
    }

    @property ListBox getSuggestionList()
    {
        return suggestionList;
    }

    void clearResults()
    {
        searchEntry.text = "";
        suggestionList.visible = false;
        suggestionList.removeAll();
    }

    void displayError(string str)
    {
        suggestionList.removeAll();

        // Add header
        ListBoxRow headerRow = new ListBoxRow();
        headerRow.selectable = false;
        Label headerLabel = new Label("Error");
        headerLabel.addCssClass("search-results-header");
        headerLabel.addCssClass("error-header");
        headerLabel.halign = Align.Start;
        headerRow.setChild(headerLabel);
        suggestionList.append(headerRow);

        ListBoxRow row = new ListBoxRow();
        row.selectable = false;

        Box rowBox = new Box(Orientation.Vertical, 4);
        rowBox.addCssClass("search-result-row");

        Label errorLabel = new Label(str);
        errorLabel.addCssClass("search-result-detail");
        errorLabel.addCssClass("error-text");
        errorLabel.halign = Align.Start;

        rowBox.append(errorLabel);
        row.setChild(rowBox);

        suggestionList.append(row);
        suggestionList.visible = true;
    }

    void displayResults(string query, string[] cids)
    {
        writeln("[Homepage] displayResults called, query: ", query, ", cids count: ", cids !is null ? cids.length : 0);
        suggestionList.removeAll();

        if (cids is null)
        {
            writeln("[Homepage] No results found");
            displayError("No results found for \""~query~"\"");
            return;
        }

        appendHeader("Search results for \""~query~"\"");

        foreach (cid; cids)
        {
            writeln("[Homepage] Adding row for CID: ", cid);
            ListBoxRow row = new ListBoxRow();
            row.setData("cid", cast(void*)cid);
            row.setChild(buildResultRow(cid));
            suggestionList.append(row);
        }

        suggestionList.visible = true;
        writeln("[Homepage] displayResults completed");
    }

    void displayResults(string query, Compound compound)
    {
        writeln("[Homepage] displayResults called, query: ", query, ", compound: ", compound !is null ? compound.name : "null");
        suggestionList.removeAll();

        if (compound is null)
        {
            writeln("[Homepage] No results found");
            displayError("No results found for \""~query~"\"");
            return;
        }

        appendHeader("Search results for \""~query~"\"");
        writeln("[Homepage] Adding row for: ", compound.name);
        ListBoxRow row = new ListBoxRow();
        row.setChild(buildResultRow(compound));
        suggestionList.append(row);
        suggestionList.visible = true;
        writeln("[Homepage] displayResults completed");
    }

    private void appendHeader(string text)
    {
        ListBoxRow headerRow = new ListBoxRow();
        headerRow.selectable = false;
        Label headerLabel = new Label(text);
        headerLabel.addCssClass("search-results-header");
        headerLabel.halign = Align.Start;
        headerRow.setChild(headerLabel);
        suggestionList.append(headerRow);
    }

    private Box buildResultRow(string cid)
    {
        Box rowBox = new Box(Orientation.Vertical, 4);
        rowBox.addCssClass("search-result-row");

        Label titleLabel = new Label("CID "~cid);
        titleLabel.addCssClass("search-result-title");
        titleLabel.halign = Align.Start;

        Label detailLabel = new Label("PubChem");
        detailLabel.addCssClass("search-result-detail");
        detailLabel.halign = Align.Start;

        rowBox.append(titleLabel);
        rowBox.append(detailLabel);
        return rowBox;
    }

    private Box buildResultRow(Compound compound)
    {
        Box rowBox = new Box(Orientation.Vertical, 4);
        rowBox.addCssClass("search-result-row");

        Label titleLabel = new Label(compound.name);
        titleLabel.addCssClass("search-result-title");
        titleLabel.halign = Align.Start;

        Label detailLabel = new Label("PubChem");
        detailLabel.addCssClass("search-result-detail");
        detailLabel.halign = Align.Start;

        rowBox.append(titleLabel);
        rowBox.append(detailLabel);
        return rowBox;
    }

    private void onSearchBtnClicked()
    {
        string text = searchEntry.text;
        if (text.length >= 2 && onSearch !is null)
            onSearch(text);
    }

    private void onSearchActivated()
    {
        string text = searchEntry.text;
        if (text.length < 2)
        {
            suggestionList.visible = false;
            suggestionList.removeAll();
            return;
        }
        if (onSearch !is null)
            onSearch(text);
    }

    private void onRowActivated(ListBoxRow row)
    {
        writeln("[Homepage] onRowActivated called");
        if (row is null || onResultSelected is null)
        {
            writeln("[Homepage] Row is null or no handler");
            return;
        }

        int index = row.getIndex();
        writeln("[Homepage] Row activated, index: ", index);
        if (index > 0)
            onResultSelected(0);
    }
}
