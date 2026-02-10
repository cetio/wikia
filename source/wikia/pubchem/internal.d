module wikia.pubchem.internal;

import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.uri : encode;
import std.string : assumeUTF;
import std.string : join;

import wikia.composer;
import wikia.pubchem.conformer3d;
import wikia.pubchem.compound;

// Names do not support batch lookup, but CID and SID do.
// TODO: PubMed ID xref support

package:

static Orchestrator orchestrator = Orchestrator("https://pubchem.ncbi.nlm.nih.gov/rest/pug", 200);

/// Fetches `Compound[]` with `cid` and `properties` populated by `/compound/%{TYPE}/%{ids}/property/`
Compound[] internalGetProperties(string TYPE)(string str)
{
    string[] props = [
        "Title", "SMILES", "IUPACName", "InChI",
        "MolecularFormula", "MolecularWeight", "ExactMass", "Charge", "TPSA", "XLogP"
    ];

    Compound[] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/compound/"~TYPE~"/"~str~"/property/"~props.join(",")~"/JSON"), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "PropertyTable" !in json || "Properties" !in json["PropertyTable"])
                throw new Exception("Properties are invalid "~json.toString());

            foreach (props; json["PropertyTable"]["Properties"].array)
            {
                Compound compound = Compound.getOrCreate(props["CID"].get!int);
                compound.properties = Properties(
                    "Title" in props ? props["Title"].str : null,
                    "SMILES" in props ? props["SMILES"].str : null,
                    "IUPACName" in props ? props["IUPACName"].str : null,
                    "InChI" in props ? props["InChI"].str : null,

                    "MolecularFormula" in props ? props["MolecularFormula"].str : null,
                    "MolecularWeight" in props ? props["MolecularWeight"].str.to!double : double.nan,
                    "ExactMass" in props ? props["ExactMass"].str.to!double : double.nan,
                    "Charge" in props ? props["Charge"].get!int : 0,
                    "TPSA" in props ? props["TPSA"].get!double : double.nan,
                    "XLogP" in props ? props["XLogP"].get!double : double.nan
                );
                ret ~= compound;
            }
        }, 
        null
    );
    return ret;
}

/// Fetches `Compound` with `cid` and `sids` populated by `/compound/%{TYPE}/%{str}/sids/JSON`
Compound[] internalGetID(string TYPE)(string str)
{
    Compound[] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/compound/"~TYPE~"/"~str~"/sids/JSON"), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "InformationList" !in json || "Information" !in json["InformationList"])
                throw new Exception("ID list is invalid "~json.toString());

            foreach (ids; json["InformationList"]["Information"].array)
            {
                Compound compound = Compound.getOrCreate(ids["CID"].get!int);
                foreach (sid; ids["SID"].array)
                    compound.sids ~= sid.get!int;
                ret ~= compound;
            }
        }, 
        null
    );
    return ret;
}

Conformer3D[] internalGetConformer3D(string TYPE)(string str)
{
    Conformer3D[] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/compound/"~TYPE~"/"~str~"/JSON", ["record_type": "3d"]), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "PC_Compounds" !in json || json["PC_Compounds"].array.length == 0)
                throw new Exception("Conformer 3D not found for "~str);

            foreach (pc; json["PC_Compounds"].array)
            {
                Conformer3D conformer = new Conformer3D();
                conformer.cid = pc["id"]["id"]["cid"].get!int;
                conformer.parseAtoms(pc);
                conformer.parseBonds(pc);
                conformer.parseCoords(pc);
                ret ~= conformer;
            }
        }, 
        null
    );
    return ret;
}

string[][] internalGetSynonyms(string TYPE)(string str)
{
    string[][] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/compound/"~TYPE~"/"~str~"/synonyms/JSON"), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "InformationList" !in json || "Information" !in json["InformationList"])
                return;

            foreach (info; json["InformationList"]["Information"].array)
            {
                string[] synonyms;
                if ("Synonym" in info)
                {
                    foreach (syn; info["Synonym"].array)
                        synonyms ~= syn.str;
                }
                ret ~= synonyms;
            }
        }, 
        null
    );
    return ret;
}

string[] internalGetDescription(string TYPE)(string str)
{
    string[] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL("/compound/"~TYPE~"/"~str~"/description/JSON"), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "InformationList" !in json || "Information" !in json["InformationList"])
                return;

            foreach (info; json["InformationList"]["Information"].array)
            {
                if ("Description" in info)
                    ret ~= info["Description"].str;
            }
        }, 
        null
    );
    return ret;
}

Compound[] internalSimilaritySearch(string TYPE)(string str, int threshold = 90, int maxRecords = 2_000_000)
{
    Compound[] ret;
    orchestrator.rateLimit();
    orchestrator.client.get(
        orchestrator.buildURL(
            "/compound/fastsimilarity_2d/"~TYPE~"/"~str~"/cids/JSON", 
            ["Threshold": threshold.to!string, "MaxRecords": maxRecords.to!string]
        ), 
        (ubyte[] data) {
            JSONValue json = parseJSON(data.assumeUTF);
            if (json.isNull || "IdentifierList" !in json || "CID" !in json["IdentifierList"])
                throw new Exception("Similarity search results are invalid "~json.toString());

            foreach (cid; json["IdentifierList"]["CID"].array)
            {
                ret ~= Compound.getOrCreate(cid.get!int);
            }
        }, 
        null
    );
    return ret;
}

private:

void parseAtoms(Conformer3D conformer, JSONValue json)
{
    if ("atoms" !in json)
        return;

    JSONValue atoms = json["atoms"];
    int[] aids;
    int[] elements;

    if ("aid" in atoms)
    {
        foreach (aid; atoms["aid"].array)
            aids ~= aid.get!int;
    }

    if ("element" in atoms)
    {
        foreach (elem; atoms["element"].array)
            elements ~= elem.get!int;
    }

    size_t atomCount = aids.length > elements.length ? elements.length : aids.length;
    foreach (size_t i; 0..atomCount)
    {
        Element elem = (elements[i] >= 1 && elements[i] <= 118)
            ? cast(Element)elements[i]
            : Element.H;
        Atom3D atom;
        atom.aid = aids[i];
        atom.element = elem;
        conformer.aidToIndex[aids[i]] = cast(int)i;
        conformer.atoms ~= atom;
    }
}

void parseBonds(Conformer3D conformer, JSONValue json)
{
    if ("bonds" !in json)
        return;

    JSONValue bonds = json["bonds"];
    int[] aid1s;
    int[] aid2s;
    int[] orders;

    if ("aid1" in bonds)
    {
        foreach (aid1; bonds["aid1"].array)
            aid1s ~= aid1.get!int;
    }

    if ("aid2" in bonds)
    {
        foreach (aid2; bonds["aid2"].array)
            aid2s ~= aid2.get!int;
    }

    if ("order" in bonds)
    {
        foreach (order; bonds["order"].array)
            orders ~= order.get!int;
    }

    size_t bondCount = aid1s.length > aid2s.length ? aid2s.length : aid1s.length;
    foreach (i; 0..bondCount)
        conformer.bonds ~= Bond3D(aid1s[i], aid2s[i], i < orders.length ? orders[i] : 1);
}

void parseCoords(Conformer3D conformer, JSONValue json)
{
    if ("coords" !in json || json["coords"].array.length == 0)
        return;

    JSONValue coordSet = json["coords"].array[0];

    if ("conformers" !in coordSet || coordSet["conformers"].array.length == 0)
        return;

    JSONValue conf = coordSet["conformers"].array[0];

    double[] xs, ys, zs;

    if ("x" in conf)
        foreach (x; conf["x"].array)
            xs ~= x.type == JSONType.float_ ? x.get!double : x.get!long.to!double;

    if ("y" in conf)
        foreach (y; conf["y"].array)
            ys ~= y.type == JSONType.float_ ? y.get!double : y.get!long.to!double;

    if ("z" in conf)
        foreach (z; conf["z"].array)
            zs ~= z.type == JSONType.float_ ? z.get!double : z.get!long.to!double;

    if ("aid" in coordSet)
    {
        JSONValue[] coordAids = coordSet["aid"].array;
        foreach (i, aid; coordAids)
        {
            int idx = conformer.indexOf(aid.get!int);
            if (idx >= 0 && i < xs.length && i < ys.length && i < zs.length)
            {
                conformer.atoms[idx].x = xs[i];
                conformer.atoms[idx].y = ys[i];
                conformer.atoms[idx].z = zs[i];
            }
        }
    }

    if ("data" in conf)
    {
        foreach (point; conf["data"].array)
        {
            if ("urn" !in point || "value" !in point)
                continue;

            JSONValue urn = point["urn"];
            JSONValue val = point["value"];

            string label = "label" in urn ? urn["label"].str : null;
            string name = "name" in urn ? urn["name"].str : null;

            if (label == "Conformer" && name == "ID" && "sval" in val)
                conformer.id = val["sval"].str;
            else if (label == "Energy" && "fval" in val)
                conformer.energy = val["fval"].get!double;
            else if (label == "Shape" && name == "Volume" && "fval" in val)
                conformer.volume = val["fval"].get!double;
            else if (label == "Shape" && name == "Self Overlap" && "fval" in val)
                conformer.selfOverlap = val["fval"].get!double;
            else if (label == "Shape" && name == "Multipoles" && "fvec" in val)
            {
                foreach (m; val["fvec"].array)
                {
                    double mval = m.type == JSONType.float_ ? m.get!double : m.get!long.to!double;
                    conformer.multipoles ~= mval;
                }
            }
        }
    }
}

/*
Similarity

This is a special type of compound namespace input that retrieves CIDs by 2D similarity search. It requires a CID, or a SMILES, InChI, or SDF string in the URL path or POST body (InChI and SDF by POST only). Valid output formats are XML, JSON(P), and ASNT/B.

Example:

https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/fastsimilarity_2d/cid/2244/cids/XML

Similarity search options are specified via URL arguments:
Option	Type	Meaning	Default
Threshold	integer	minimum Tanimoto score for a hit	90
MaxSeconds	integer	maximum search time in seconds	unlimited
MaxRecords	integer	maximum number of hits	2M
listkey	string	restrict to matches within hits from a prior search	none

Example:

https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/fastsimilarity_2d/smiles/C1=NC2=C(N1)C(=O)N=C(N2)N/cids/XML?Threshold=95&MaxRecords=100
*/