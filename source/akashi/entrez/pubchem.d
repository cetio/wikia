module akashi.entrez.pubchem;

import std.net.curl : get;
import std.json : JSONValue, parseJSON;
import std.uri : encode;
import std.conv : to;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;
import std.string : indexOf, strip;
import std.algorithm : map;
import std.array : array, join;

private enum pubchemBase = "https://pubchem.ncbi.nlm.nih.gov/rest/pug";

// Rate limiting: 5 requests/second recommended
private SysTime lastRequestTime = SysTime.init;
private const Duration minRequestInterval = dur!"msecs"(200); // 200ms (5 req/sec)

private void rateLimit()
{
    auto now = Clock.currTime();
    auto elapsed = now - lastRequestTime;
    if (elapsed < minRequestInterval)
    {
        Thread.sleep(minRequestInterval - elapsed);
    }
    lastRequestTime = Clock.currTime();
}

struct PubChemCompound
{
    string cid;
    string molecularFormula;
    double molecularWeight;
    string iupacName;
    string canonicalSMILES;
    string isomericSMILES;
    string inchi;
    string inchiKey;
    JSONValue fullData; // For configurable access to all properties
}

// Get compound by CID
PubChemCompound getCompound(string cid)
{
    rateLimit();
    
    // Get all common properties
    string[] properties = [
        "MolecularFormula",
        "MolecularWeight",
        "IUPACName",
        "CanonicalSMILES",
        "IsomericSMILES",
        "InChI",
        "InChIKey"
    ];
    
    JSONValue props = getProperties(cid, properties);
    
    PubChemCompound compound;
    compound.cid = cid;
    
    if (!props.isNull && "PropertyTable" in props && "Properties" in props["PropertyTable"])
    {
        JSONValue propList = props["PropertyTable"]["Properties"];
        if (propList.array.length > 0)
        {
            JSONValue p = propList.array[0];
            
            if ("MolecularFormula" in p)
                compound.molecularFormula = p["MolecularFormula"].str;
            if ("MolecularWeight" in p)
            {
                string mw = p["MolecularWeight"].str;
                try
                {
                    compound.molecularWeight = mw.to!double;
                }
                catch (Exception) {}
            }
            if ("IUPACName" in p)
                compound.iupacName = p["IUPACName"].str;
            // API returns "SMILES" for CanonicalSMILES request
            if ("SMILES" in p)
                compound.canonicalSMILES = p["SMILES"].str;
            if ("IsomericSMILES" in p)
                compound.isomericSMILES = p["IsomericSMILES"].str;
            if ("InChI" in p)
                compound.inchi = p["InChI"].str;
            if ("InChIKey" in p)
                compound.inchiKey = p["InChIKey"].str;
        }
    }
    
    // Store full property data
    compound.fullData = props;
    
    return compound;
}

// Search by name
PubChemCompound[] searchByName(string name, int limit = 10)
{
    rateLimit();
    
    string url = pubchemBase~"/compound/name/"~encode(name)~"/cids/JSON";
    
    JSONValue json = parseJSON(get(url).idup);
    if (json.isNull || !("IdentifierList" in json) || !("CID" in json["IdentifierList"]))
        return [];
    
    string[] cids = json["IdentifierList"]["CID"].array.map!(x => x.to!string).array;
    
    // Limit results
    if (cids.length > limit)
        cids = cids[0..limit];
    
    // Get compounds for each CID
    PubChemCompound[] compounds;
    foreach (cid; cids)
    {
        compounds ~= getCompound(cid);
    }
    
    return compounds;
}

// Get specific properties
JSONValue getProperties(string cid, string[] propertyNames)
{
    rateLimit();
    
    string props = propertyNames.join(",");
    string url = pubchemBase~"/compound/cid/"~cid~"/property/"~props~"/JSON";
    
    return parseJSON(get(url).idup);
}

// Get all available properties (common ones)
string[] getAvailableProperties()
{
    return [
        "MolecularFormula",
        "MolecularWeight",
        "IUPACName",
        "CanonicalSMILES",
        "IsomericSMILES",
        "InChI",
        "InChIKey",
        "XLogP",
        "ExactMass",
        "MonoisotopicMass",
        "TPSA",
        "Complexity",
        "Charge",
        "HBondDonorCount",
        "HBondAcceptorCount",
        "RotatableBondCount",
        "HeavyAtomCount",
        "IsotopeAtomCount",
        "AtomStereoCount",
        "DefinedAtomStereoCount",
        "UndefinedAtomStereoCount",
        "BondStereoCount",
        "DefinedBondStereoCount",
        "UndefinedBondStereoCount",
        "CovalentUnitCount",
        "Volume3D",
        "XStericQuadrupole3D",
        "YStericQuadrupole3D",
        "ZStericQuadrupole3D",
        "FeatureCount3D",
        "FeatureAcceptorCount3D",
        "FeatureDonorCount3D",
        "FeatureAnionCount3D",
        "FeatureCationCount3D",
        "FeatureRingCount3D",
        "FeatureHydrophobeCount3D",
        "ConformerModelRMSD3D",
        "EffectiveRotorCount3D",
        "ConformerCount3D"
    ];
}

// Get descriptions
JSONValue getDescriptions(string cid)
{
    rateLimit();
    
    string url = pubchemBase~"/compound/cid/"~cid~"/description/JSON";
    
    return parseJSON(get(url).idup);
}

// Get synonyms
JSONValue getSynonyms(string cid)
{
    rateLimit();
    
    string url = pubchemBase~"/compound/cid/"~cid~"/synonyms/JSON";
    
    return parseJSON(get(url).idup);
}

unittest
{
    // Test with known CID for arketamine
    PubChemCompound compound = getCompound("644025");
    assert(compound.cid == "644025", "CID should match");
    assert(compound.molecularFormula == "C13H16ClNO", "Molecular formula should match arketamine");
    assert(compound.molecularWeight > 237.0 && compound.molecularWeight < 238.0, "Molecular weight should be ~237.72");
    assert(compound.iupacName.length > 0, "IUPAC name should be present");
    assert(compound.canonicalSMILES.length > 0, "SMILES should be present");
}

unittest
{
    // Test search by name
    PubChemCompound[] compounds = searchByName("arketamine", 3);
    assert(compounds.length > 0, "Search should return at least one result");
    assert(compounds[0].cid == "644025", "First result should be arketamine (CID 644025)");
}

unittest
{
    // Test property retrieval
    string[] props = ["MolecularFormula", "MolecularWeight"];
    JSONValue result = getProperties("644025", props);
    assert(!result.isNull, "Property retrieval should succeed");
    assert("PropertyTable" in result, "Should have PropertyTable");
    assert("Properties" in result["PropertyTable"], "Should have Properties array");
    if (result["PropertyTable"]["Properties"].array.length > 0)
    {
        JSONValue p = result["PropertyTable"]["Properties"].array[0];
        assert("MolecularFormula" in p, "Should have MolecularFormula");
        assert(p["MolecularFormula"].str == "C13H16ClNO", "Molecular formula should match");
    }
}

unittest
{
    // Test descriptions
    JSONValue descs = getDescriptions("644025");
    assert(!descs.isNull, "Description retrieval should succeed");
    assert("InformationList" in descs, "Should have InformationList");
}