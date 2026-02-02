module akashi.entrez.pubchem;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.uri : encode;
import std.conv : to;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;
import std.string : indexOf, strip;
import std.algorithm : map, canFind, min;
import std.array : array, join;

struct Compound
{
    JSONValue json;

    string cid;
    string molecularFormula;
    double molecularWeight;
    string iupacName;
    string canonicalSMILES;
    string isomericSMILES;
    string inchi;
    string inchiKey;
}

class Atom3D
{
    // Atom ID
    int aid;
    // Atomic number (1=H, 6=C, 7=N, 8=O, etc.)
    int element;
    // 3D coordinates
    double x, y, z;

    this(int aid, int element)
    {
        this.aid = aid;
        this.element = element;
    }

    string elementSymbol() const
    {
        switch (element)
        {
            case 1: return "H";
            case 6: return "C";
            case 7: return "N";
            case 8: return "O";
            case 9: return "F";
            case 15: return "P";
            case 16: return "S";
            case 17: return "Cl";
            case 35: return "Br";
            case 53: return "I";
            default: return "?";
        }
    }
}

struct Bond3D
{
    // Atom IDs for the bond
    int aid1, aid2;
    // Bond order (1=single, 2=double, 3=triple)
    int order;
}

struct Conformer3D
{
    JSONValue json;
    
    string cid;
    string conformerId;
    Atom3D[] atoms;
    Bond3D[] bonds;
    // MMFF94 energy
    double energy;
    // Shape volume
    double volume;
    // Shape self overlap
    double selfOverlap;
    // Shape multipoles
    double[] multipoles;

    bool isValid() const
    {
        return atoms.length > 0;
    }

    Atom3D getAtomById(int aid)
    {
        foreach (ref atom; atoms)
        {
            if (atom.aid == aid)
                return atom;
        }
        return null;
    }
}

static class PubChem
{
    private enum baseURL = "https://pubchem.ncbi.nlm.nih.gov/rest/pug";

    // Rate limiting: 5 requests/second recommended
    private static SysTime lastRequestTime = SysTime.init;
    private static const Duration minRequestInterval = dur!"msecs"(200); // 200ms (5 req/sec)

    private static void rateLimit()
    {
        SysTime now = Clock.currTime();
        Duration elapsed = now - lastRequestTime;
        if (elapsed < minRequestInterval)
            Thread.sleep(minRequestInterval - elapsed);
        lastRequestTime = Clock.currTime();
    }

    static Compound getCompound(string cid)
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
        
        Compound compound;
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
                    compound.molecularWeight = p["MolecularWeight"].str.to!double;
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
        compound.json = props;
        
        return compound;
    }

    static Compound[] searchByName(string name, int limit = 10)
    {
        rateLimit();
        
        string url = baseURL~"/compound/name/"~encode(name)~"/cids/JSON";
        
        JSONValue json = parseJSON(get(url).idup);
        if (json.isNull || !("IdentifierList" in json) || !("CID" in json["IdentifierList"]))
            return [];
        
        string[] cids = json["IdentifierList"]["CID"].array.map!(x => x.to!string).array;
        
        // Limit results
        if (cids.length > limit)
            cids = cids[0..limit];
        
        // Get compounds for each CID
        Compound[] compounds;
        foreach (cid; cids)
            compounds ~= getCompound(cid);
        
        return compounds;
    }

    static JSONValue getProperties(string cid, string[] propertyNames)
    {
        rateLimit();
        
        string props = propertyNames.join(",");
        string url = baseURL~"/compound/cid/"~cid~"/property/"~props~"/JSON";
        
        return parseJSON(get(url).idup);
    }

    static string[] getAvailableProperties()
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

    static JSONValue getDescriptions(string cid)
    {
        rateLimit();
        
        string url = baseURL~"/compound/cid/"~cid~"/description/JSON";
        
        return parseJSON(get(url).idup);
    }

    static JSONValue getSynonyms(string cid)
    {
        rateLimit();
        
        string url = baseURL~"/compound/cid/"~cid~"/synonyms/JSON";
        
        return parseJSON(get(url).idup);
    }

    static Conformer3D getConformer3D(string cid)
    {
        rateLimit();
        
        string url = baseURL~"/compound/cid/"~cid~"/JSON?record_type=3d";
        
        Conformer3D conformer;
        conformer.cid = cid;
        
        JSONValue json = parseJSON(get(url).idup);
        conformer.json = json;
        
        if ("PC_Compounds" !in json)
            throw new Exception("Conformer is not valid: "~json.toString);
        
        JSONValue compounds = json["PC_Compounds"];
        if (compounds.array.length == 0)
            throw new Exception("Conformer is not valid: "~json.toString);
        
        JSONValue compound = compounds.array[0];
        
        // Parse atoms
        if ("atoms" in compound)
        {
            JSONValue atoms = compound["atoms"];
            int[] aids;
            int[] elements;
            
            if ("aid" in atoms)
            {
                foreach (a; atoms["aid"].array)
                    aids ~= a.get!int;
            }
            
            if ("element" in atoms)
            {
                foreach (e; atoms["element"].array)
                    elements ~= e.get!int;
            }
            
            foreach (i; 0..aids.length)
                conformer.atoms ~= new Atom3D(aids[i], elements[i]);
        }
        
        // Parse bonds
        if ("bonds" in compound)
        {
            JSONValue bonds = compound["bonds"];
            int[] aid1s, aid2s, orders;
            
            if ("aid1" in bonds)
            {
                foreach (a; bonds["aid1"].array)
                    aid1s ~= a.get!int;
            }
            
            if ("aid2" in bonds)
            {
                foreach (a; bonds["aid2"].array)
                    aid2s ~= a.get!int;
            }
            
            if ("order" in bonds)
            {
                foreach (o; bonds["order"].array)
                    orders ~= o.get!int;
            }

            size_t bondCount = min(aid1s.length, aid2s.length);
            foreach (i; 0..bondCount)
                conformer.bonds ~= Bond3D(aid1s[i], aid2s[i], i < orders.length ? orders[i] : 1);
        }
        
        // Parse 3D coordinates
        if ("coords" in compound && compound["coords"].array.length > 0)
        {
            JSONValue coordSet = compound["coords"].array[0];
            
            if ("conformers" in coordSet && coordSet["conformers"].array.length > 0)
            {
                JSONValue conf = coordSet["conformers"].array[0];
                
                double[] xs, ys, zs;
                
                if ("x" in conf)
                    foreach (v; conf["x"].array)
                        xs ~= v.type == JSONType.float_ ? v.get!double : v.get!long.to!double;
                
                if ("y" in conf)
                    foreach (v; conf["y"].array)
                        ys ~= v.type == JSONType.float_ ? v.get!double : v.get!long.to!double;
                
                if ("z" in conf)
                    foreach (v; conf["z"].array)
                        zs ~= v.type == JSONType.float_ ? v.get!double : v.get!long.to!double;
                
                // Match coordinates to atoms by index (aid array order matches coord order)
                if ("aid" in coordSet)
                {
                    JSONValue[] coordAids = coordSet["aid"].array;
                    foreach (i, val; coordAids)
                    {
                        int aid = val.get!int;
                        Atom3D atom = conformer.getAtomById(aid);
                        if (atom !is null && i < xs.length && i < ys.length && i < zs.length)
                        {
                            atom.x = xs[i];
                            atom.y = ys[i];
                            atom.z = zs[i];
                        }
                    }
                }
                
                // Parse conformer metadata
                if ("data" in conf)
                {
                    foreach (point; conf["data"].array)
                    {
                        if ("urn" in point && "value" in point)
                        {
                            JSONValue urn = point["urn"];
                            JSONValue val = point["value"];
                            
                            string label = "label" in urn ? urn["label"].str : null;
                            string name = "name" in urn ? urn["name"].str : null;
                            
                            if (label == "Conformer" && name == "ID" && "sval" in val)
                                conformer.conformerId = val["sval"].str;
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
            }
        }
        
        return conformer;
    }
}

unittest
{
    // Test with known CID for arketamine
    Compound compound = PubChem.getCompound("644025");
    assert(compound.cid == "644025", "CID should match");
    assert(compound.molecularFormula == "C13H16ClNO", "Molecular formula should match arketamine");
    assert(compound.molecularWeight > 237.0 && compound.molecularWeight < 238.0, "Molecular weight should be ~237.72");
    assert(compound.iupacName.length > 0, "IUPAC name should be present");
    assert(compound.canonicalSMILES.length > 0, "SMILES should be present");
}

unittest
{
    // Test search by name
    Compound[] compounds = PubChem.searchByName("arketamine", 3);
    assert(compounds.length > 0, "Search should return at least one result");
    assert(compounds[0].cid == "644025", "First result should be arketamine (CID 644025)");
}

unittest
{
    // Test property retrieval
    string[] props = ["MolecularFormula", "MolecularWeight"];
    JSONValue result = PubChem.getProperties("644025", props);
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
    JSONValue descs = PubChem.getDescriptions("644025");
    assert(!descs.isNull, "Description retrieval should succeed");
    assert("InformationList" in descs, "Should have InformationList");
}

unittest
{
    // Test synonyms
    JSONValue synonyms = PubChem.getSynonyms("644025");
    assert(!synonyms.isNull, "Synonyms retrieval should succeed");
}

unittest
{
    // Test available properties
    string[] props = PubChem.getAvailableProperties();
    assert(props.length > 0, "Should return available properties");
    assert(props.canFind("MolecularFormula") >= 0, "Should include MolecularFormula");
    assert(props.canFind("MolecularWeight") >= 0, "Should include MolecularWeight");
}

unittest
{
    // Test search with different compound
    Compound[] compounds = PubChem.searchByName("aspirin", 2);
    if (compounds.length > 0)
    {
        assert(compounds[0].cid.length > 0, "Compound should have CID");
    }
}

unittest
{
    // Test 4-HO-MET search by name
    Compound[] compounds = PubChem.searchByName("4-HO-MET", 3);
    assert(compounds.length > 0, "4-HO-MET search should return results");
    // 4-HO-MET has CID 21786582
    assert(compounds[0].cid == "21786582", "First result should be 4-HO-MET (CID 21786582)");
}

unittest
{
    // Test 4-HO-MET compound retrieval
    Compound compound = PubChem.getCompound("21786582");
    assert(compound.cid == "21786582", "CID should match 4-HO-MET");
    assert(compound.molecularFormula.length > 0, "Should have molecular formula");
    assert(compound.iupacName.length > 0, "Should have IUPAC name");
    assert(compound.canonicalSMILES.length > 0, "Should have SMILES");
}

unittest
{
    // Test 4-HO-MET 3D conformer retrieval
    Conformer3D conformer = PubChem.getConformer3D("21786582");
    assert(conformer.isValid(), "4-HO-MET should have valid 3D conformer");
    assert(conformer.cid == "21786582", "Conformer CID should match");
    assert(conformer.atoms.length > 0, "Should have atoms");
    assert(conformer.bonds.length > 0, "Should have bonds");
    
    // Verify atom data
    bool hasCarbon = false;
    bool hasNitrogen = false;
    bool hasOxygen = false;
    foreach (atom; conformer.atoms)
    {
        if (atom.element == 6) hasCarbon = true;
        if (atom.element == 7) hasNitrogen = true;
        if (atom.element == 8) hasOxygen = true;
    }
    assert(hasCarbon, "Should have carbon atoms");
    assert(hasNitrogen, "Should have nitrogen atoms");
    assert(hasOxygen, "Should have oxygen atoms");
}

unittest
{
    // Test 4-HO-MET 3D conformer coordinates
    Conformer3D conformer = PubChem.getConformer3D("21786582");
    assert(conformer.isValid(), "Conformer should be valid");
    
    // Verify coordinates are populated (not all zero)
    bool hasNonZeroCoord = false;
    foreach (atom; conformer.atoms)
    {
        if (atom.x != 0.0 || atom.y != 0.0 || atom.z != 0.0)
        {
            hasNonZeroCoord = true;
            break;
        }
    }
    assert(hasNonZeroCoord, "Should have non-zero 3D coordinates");
    
    // Verify conformer metadata
    assert(conformer.conformerId.length > 0, "Should have conformer ID");
}
