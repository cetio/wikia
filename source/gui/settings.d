module gui.settings;

import std.stdio : writeln;
import std.conv : to;
import std.algorithm : canFind;
import std.array : join;

import gtk.box;
import gtk.image;
import gtk.label;
import gtk.button;
import gtk.check_button;
import gtk.entry;
import gtk.stack;
import gtk.window;
import gtk.types : Orientation, Align, InputPurpose;
import gtk.widget : Widget;

import infer.config;

class SettingsWindow : Window
{
private:
    Entry endpointEntry;
    Entry apiKeyEntry;
    Entry chatModelEntry;
    Entry embedModelEntry;
    Entry groupThreshEntry;
    Entry dedupeThreshEntry;
    CheckButton rabbitHolesCheck;
    CheckButton srcWikipediaCheck;
    CheckButton srcPsychonautCheck;
    Window parent;

    Button[] tabButtons;
    Stack contentStack;

    Box buildEntryRow(string labelText, Entry field, string placeholder = "")
    {
        Box row = new Box(Orientation.Vertical, 2);
        row.addCssClass("settings-row");
        row.hexpand = true;
        row.halign = Align.Fill;

        Label lbl = new Label(labelText);
        lbl.addCssClass("settings-label");
        lbl.halign = Align.Start;
        row.append(lbl);

        field.addCssClass("settings-entry");
        field.hexpand = true;
        field.halign = Align.Fill;
        if (placeholder.length > 0)
            field.placeholderText = placeholder;
        row.append(field);

        return row;
    }

    static Label buildSectionTitle(string text)
    {
        Label title = new Label(text);
        title.addCssClass("settings-section-title");
        title.halign = Align.Start;
        title.marginTop = 12;
        title.marginBottom = 4;
        return title;
    }

    void selectTab(int index)
    {
        foreach (i, btn; tabButtons)
        {
            if (i == index)
                btn.addCssClass("settings-tab-active");
            else
                btn.removeCssClass("settings-tab-active");
        }

        final switch (index)
        {
            case 0: contentStack.visibleChildName = "inference"; break;
            case 1: contentStack.visibleChildName = "retrieval"; break;
            case 2: contentStack.visibleChildName = "style"; break;
        }
    }

    Box buildInferenceTab()
    {
        Box tab = new Box(Orientation.Vertical, 4);
        tab.addCssClass("settings-section");

        InferConfig cfg = config();

        // --- Local AI ---
        tab.append(buildSectionTitle("Local AI"));

        endpointEntry = new Entry();
        endpointEntry.text = cfg.endpoint;
        tab.append(buildEntryRow("Endpoint", endpointEntry, "http://127.0.0.1:1234/"));

        apiKeyEntry = new Entry();
        if (cfg.apiKey.length > 0)
            apiKeyEntry.text = cfg.apiKey;
        apiKeyEntry.inputPurpose = InputPurpose.Password;
        apiKeyEntry.visibility = false;
        tab.append(buildEntryRow("API Key", apiKeyEntry, "sk-... (optional for local)"));

        chatModelEntry = new Entry();
        chatModelEntry.text = cfg.chatModel;
        tab.append(buildEntryRow("Chat Model", chatModelEntry, "model name or path"));

        embedModelEntry = new Entry();
        embedModelEntry.text = cfg.embedModel;
        tab.append(buildEntryRow("Embed Model", embedModelEntry, "embedding model name"));

        groupThreshEntry = new Entry();
        groupThreshEntry.text = cfg.groupingThreshold.to!string;
        tab.append(buildEntryRow("Group Threshold", groupThreshEntry, "0.75"));

        dedupeThreshEntry = new Entry();
        dedupeThreshEntry.text = cfg.dedupeThreshold.to!string;
        tab.append(buildEntryRow("Dedup Threshold", dedupeThreshEntry, "0.92"));

        // --- Interface ---
        tab.append(buildSectionTitle("Interface"));

        rabbitHolesCheck = new CheckButton();
        rabbitHolesCheck.label = "Auto resolve rabbit-holes";
        rabbitHolesCheck.active = cfg.autoResolveRabbitHoles;
        rabbitHolesCheck.marginTop = 4;
        tab.append(rabbitHolesCheck);

        return tab;
    }

    Box buildSourceRow(string iconPath, string sourceName, ref CheckButton check, bool active)
    {
        Box row = new Box(Orientation.Horizontal, 8);
        row.addCssClass("settings-source-row");
        row.halign = Align.Fill;
        row.hexpand = true;
        row.marginStart = 4;
        row.marginTop = 2;
        row.marginBottom = 2;

        Image icon = Image.newFromFile(iconPath);
        icon.pixelSize = 16;
        row.append(icon);

        check = new CheckButton();
        check.label = sourceName;
        check.active = active;
        check.addCssClass("settings-source-check");
        row.append(check);

        return row;
    }

    Box buildRetrievalTab()
    {
        Box tab = new Box(Orientation.Vertical, 4);
        tab.addCssClass("settings-section");

        InferConfig cfg = config();

        tab.append(buildSectionTitle("Sources"));

        tab.append(buildSourceRow(
            "resources/icons/wikipedia.svg", "Wikipedia",
            srcWikipediaCheck, cfg.enabledSources.canFind("wikipedia")));

        tab.append(buildSourceRow(
            "resources/icons/psychonaut.svg", "Psychonaut Wiki",
            srcPsychonautCheck, cfg.enabledSources.canFind("psychonaut")));

        return tab;
    }

    static Box buildPlaceholderTab(string text)
    {
        Box tab = new Box(Orientation.Vertical, 0);
        tab.addCssClass("settings-section");
        tab.halign = Align.Center;
        tab.valign = Align.Center;
        tab.vexpand = true;

        Label placeholder = new Label(text);
        placeholder.addCssClass("settings-placeholder");
        tab.append(placeholder);
        return tab;
    }

public:
    this(Window parent)
    {
        super();
        this.parent = parent;
        if (parent !is null)
            setTransientFor(parent);
        setTitle("Settings");
        addCssClass("settings-window");

        Box root = new Box(Orientation.Vertical, 0);

        // Tab bar
        Box tabBar = new Box(Orientation.Horizontal, 0);
        tabBar.addCssClass("settings-tab-bar");
        tabBar.halign = Align.Fill;
        tabBar.hexpand = true;

        string[3] tabNames = ["Inference", "Retrieval", "Style"];
        foreach (i, name; tabNames)
        {
            Button tab = new Button();
            tab.label = name;
            tab.addCssClass("settings-tab");
            tab.connectClicked(((int idx) => () { selectTab(idx); })(cast(int)i));
            tabBar.append(tab);
            tabButtons ~= tab;
        }
        root.append(tabBar);

        // Content stack
        contentStack = new Stack();
        contentStack.hexpand = true;
        contentStack.vexpand = true;

        contentStack.addNamed(buildInferenceTab(), "inference");
        contentStack.addNamed(buildRetrievalTab(), "retrieval");
        contentStack.addNamed(buildPlaceholderTab("Style settings coming soon."), "style");
        contentStack.visibleChildName = "inference";

        root.append(contentStack);

        // Apply button
        Box footer = new Box(Orientation.Horizontal, 0);
        footer.halign = Align.End;
        footer.marginTop = 8;
        footer.marginEnd = 16;
        footer.marginBottom = 12;

        Button applyBtn = new Button();
        applyBtn.label = "Apply";
        applyBtn.addCssClass("settings-apply");
        applyBtn.connectClicked(&onApply);
        footer.append(applyBtn);
        root.append(footer);

        setChild(root);
        selectTab(0);
    }

    void setSizeFromParent()
    {
        int w = 1200;
        int h = 800;
        if (parent !is null)
        {
            int pw = parent.getAllocatedWidth();
            int ph = parent.getAllocatedHeight();
            if (pw > 0) w = pw;
            if (ph > 0) h = ph;
        }
        setDefaultSize(w / 3, h);
    }

    void open()
    {
        setSizeFromParent();
        present();
    }

    void onApply()
    {
        InferConfig cfg;
        cfg.endpoint = endpointEntry.text;
        cfg.apiKey = apiKeyEntry.text;
        cfg.chatModel = chatModelEntry.text;
        cfg.embedModel = embedModelEntry.text;
        cfg.autoResolveRabbitHoles = rabbitHolesCheck.active;

        try
            cfg.groupingThreshold = groupThreshEntry.text.to!float;
        catch (Exception e)
            cfg.groupingThreshold = 0.75;

        try
            cfg.dedupeThreshold = dedupeThreshEntry.text.to!float;
        catch (Exception e)
            cfg.dedupeThreshold = 0.92;

        string[] sources;
        if (srcWikipediaCheck.active) sources ~= "wikipedia";
        if (srcPsychonautCheck.active) sources ~= "psychonaut";
        cfg.enabledSources = sources;

        setConfig(cfg);
        writeln("[Settings] Config updated: endpoint=", cfg.endpoint,
            " chat=", cfg.chatModel, " embed=", cfg.embedModel,
            " rabbitHoles=", cfg.autoResolveRabbitHoles,
            " sources=", cfg.enabledSources);

        close();
    }
}
