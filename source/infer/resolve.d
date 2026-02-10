module infer.resolve;

import std.regex : ctRegex, matchAll;
import std.string : toLower;
import infer.config;

private:

// INN/pharmaceutical suffixes (5+ chars to reduce false positives).
immutable string[] suffixes = [
    "amine", "azine", "azole", "caine", "cillin",
    "cline", "idine", "mycin", "ophen", "orphan",
    "profen", "ridol", "sartan", "setron", "statin",
    "tadine", "terol", "thiazide", "tidine", "tinib",
    "triptan", "xaban", "zepam", "zodone", "zosin",
    "olol", "pril", "oxin",
];

// Common English words that match drug suffixes but aren't compounds.
immutable string[] exclusions = [
    "determine", "examine", "famine", "amine", "amine",
    "machine", "routine", "pristine", "magazine", "alpine",
    "discipline", "doctrine", "medicine", "gasoline",
    "genuine", "imagine", "feminine", "masculine",
    "antine", "antine", "decline", "combine", "online",
    "done", "gone", "bone", "tone", "zone", "phone",
    "pine", "mine", "fine", "line", "wine", "vine",
    "determine", "undermine", "sunshine", "outline",
];

bool hasDrugSuffix(string word)
{
    string lower = word.toLower;
    foreach (ex; exclusions)
    {
        if (lower == ex)
            return false;
    }

    foreach (suf; suffixes)
    {
        if (lower.length > suf.length && lower[$ - suf.length .. $] == suf)
            return true;
    }
    return false;
}

public:

string[] extractCompoundNames(string text)
{
    auto cfg = config();
    if (!cfg.autoResolveRabbitHoles)
        return [];

    string trunc = text.length > 2000 ? text[0 .. 2000] : text;
    bool[string] names;

    // Suffix-matched drug names (e.g. ketamine, phencyclidine, midazolam)
    enum wordRe = ctRegex!(`[\w]{6,}`);
    foreach (m; matchAll(trunc, wordRe))
    {
        if (m.hit.hasDrugSuffix)
            names[m.hit] = true;
    }

    // IUPAC-style names (contain parentheses + hyphens in chemical context)
    enum iupacRe = ctRegex!(`\d+(?:,\d+)*-\([A-Za-z,]+\)-[A-Za-z][A-Za-z0-9-]*`);
    foreach (m; matchAll(trunc, iupacRe))
        names[m.hit] = true;

    // Number-prefixed compounds (2C-B, 5-MeO-DMT, 4-AcO-DMT)
    // Require uppercase letter after final hyphen; at least 3 chars total.
    enum numCompoundRe = ctRegex!(`\d+[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)+`);
    foreach (m; matchAll(trunc, numCompoundRe))
        names[m.hit] = true;

    return names.keys;
}
