module wikia.pubchem.conformer3d;

enum Element : int
{
    H = 1, He = 2, Li = 3, Be = 4, B = 5, C = 6, N = 7, O = 8, F = 9, Ne = 10,
    Na = 11, Mg = 12, Al = 13, Si = 14, P = 15, S = 16, Cl = 17, Ar = 18,
    K = 19, Ca = 20, Sc = 21, Ti = 22, V = 23, Cr = 24, Mn = 25, Fe = 26,
    Co = 27, Ni = 28, Cu = 29, Zn = 30, Ga = 31, Ge = 32, As = 33, Se = 34,
    Br = 35, Kr = 36, Rb = 37, Sr = 38, Y = 39, Zr = 40, Nb = 41, Mo = 42,
    Tc = 43, Ru = 44, Rh = 45, Pd = 46, Ag = 47, Cd = 48, In = 49, Sn = 50,
    Sb = 51, Te = 52, I = 53, Xe = 54, Cs = 55, Ba = 56, La = 57, Ce = 58,
    Pr = 59, Nd = 60, Pm = 61, Sm = 62, Eu = 63, Gd = 64, Tb = 65, Dy = 66,
    Ho = 67, Er = 68, Tm = 69, Yb = 70, Lu = 71, Hf = 72, Ta = 73, W = 74,
    Re = 75, Os = 76, Ir = 77, Pt = 78, Au = 79, Hg = 80, Tl = 81, Pb = 82,
    Bi = 83, Po = 84, At = 85, Rn = 86, Fr = 87, Ra = 88, Ac = 89, Th = 90,
    Pa = 91, U = 92, Np = 93, Pu = 94, Am = 95, Cm = 96, Bk = 97, Cf = 98,
    Es = 99, Fm = 100, Md = 101, No = 102, Lr = 103, Rf = 104, Db = 105,
    Sg = 106, Bh = 107, Hs = 108, Mt = 109, Ds = 110, Rg = 111, Cn = 112,
    Nh = 113, Fl = 114, Mc = 115, Lv = 116, Ts = 117, Og = 118
}

string name(Element elem)
{
    switch (elem)
    {
        case Element.H: return "Hydrogen";
        case Element.He: return "Helium";
        case Element.Li: return "Lithium";
        case Element.Be: return "Beryllium";
        case Element.B: return "Boron";
        case Element.C: return "Carbon";
        case Element.N: return "Nitrogen";
        case Element.O: return "Oxygen";
        case Element.F: return "Fluorine";
        case Element.Ne: return "Neon";
        case Element.Na: return "Sodium";
        case Element.Mg: return "Magnesium";
        case Element.Al: return "Aluminum";
        case Element.Si: return "Silicon";
        case Element.P: return "Phosphorus";
        case Element.S: return "Sulfur";
        case Element.Cl: return "Chlorine";
        case Element.Ar: return "Argon";
        case Element.K: return "Potassium";
        case Element.Ca: return "Calcium";
        case Element.Sc: return "Scandium";
        case Element.Ti: return "Titanium";
        case Element.V: return "Vanadium";
        case Element.Cr: return "Chromium";
        case Element.Mn: return "Manganese";
        case Element.Fe: return "Iron";
        case Element.Co: return "Cobalt";
        case Element.Ni: return "Nickel";
        case Element.Cu: return "Copper";
        case Element.Zn: return "Zinc";
        case Element.Ga: return "Gallium";
        case Element.Ge: return "Germanium";
        case Element.As: return "Arsenic";
        case Element.Se: return "Selenium";
        case Element.Br: return "Bromine";
        case Element.Kr: return "Krypton";
        case Element.Rb: return "Rubidium";
        case Element.Sr: return "Strontium";
        case Element.Y: return "Yttrium";
        case Element.Zr: return "Zirconium";
        case Element.Nb: return "Niobium";
        case Element.Mo: return "Molybdenum";
        case Element.Tc: return "Technetium";
        case Element.Ru: return "Ruthenium";
        case Element.Rh: return "Rhodium";
        case Element.Pd: return "Palladium";
        case Element.Ag: return "Silver";
        case Element.Cd: return "Cadmium";
        case Element.In: return "Indium";
        case Element.Sn: return "Tin";
        case Element.Sb: return "Antimony";
        case Element.Te: return "Tellurium";
        case Element.I: return "Iodine";
        case Element.Xe: return "Xenon";
        case Element.Cs: return "Cesium";
        case Element.Ba: return "Barium";
        case Element.La: return "Lanthanum";
        case Element.Ce: return "Cerium";
        case Element.Pr: return "Praseodymium";
        case Element.Nd: return "Neodymium";
        case Element.Pm: return "Promethium";
        case Element.Sm: return "Samarium";
        case Element.Eu: return "Europium";
        case Element.Gd: return "Gadolinium";
        case Element.Tb: return "Terbium";
        case Element.Dy: return "Dysprosium";
        case Element.Ho: return "Holmium";
        case Element.Er: return "Erbium";
        case Element.Tm: return "Thulium";
        case Element.Yb: return "Ytterbium";
        case Element.Lu: return "Lutetium";
        case Element.Hf: return "Hafnium";
        case Element.Ta: return "Tantalum";
        case Element.W: return "Tungsten";
        case Element.Re: return "Rhenium";
        case Element.Os: return "Osmium";
        case Element.Ir: return "Iridium";
        case Element.Pt: return "Platinum";
        case Element.Au: return "Gold";
        case Element.Hg: return "Mercury";
        case Element.Tl: return "Thallium";
        case Element.Pb: return "Lead";
        case Element.Bi: return "Bismuth";
        case Element.Po: return "Polonium";
        case Element.At: return "Astatine";
        case Element.Rn: return "Radon";
        case Element.Fr: return "Francium";
        case Element.Ra: return "Radium";
        case Element.Ac: return "Actinium";
        case Element.Th: return "Thorium";
        case Element.Pa: return "Protactinium";
        case Element.U: return "Uranium";
        case Element.Np: return "Neptunium";
        case Element.Pu: return "Plutonium";
        case Element.Am: return "Americium";
        case Element.Cm: return "Curium";
        case Element.Bk: return "Berkelium";
        case Element.Cf: return "Californium";
        case Element.Es: return "Einsteinium";
        case Element.Fm: return "Fermium";
        case Element.Md: return "Mendelevium";
        case Element.No: return "Nobelium";
        case Element.Lr: return "Lawrencium";
        case Element.Rf: return "Rutherfordium";
        case Element.Db: return "Dubnium";
        case Element.Sg: return "Seaborgium";
        case Element.Bh: return "Bohrium";
        case Element.Hs: return "Hassium";
        case Element.Mt: return "Meitnerium";
        case Element.Ds: return "Darmstadtium";
        case Element.Rg: return "Roentgenium";
        case Element.Cn: return "Copernicium";
        case Element.Nh: return "Nihonium";
        case Element.Fl: return "Flerovium";
        case Element.Mc: return "Moscovium";
        case Element.Lv: return "Livermorium";
        case Element.Ts: return "Tennessine";
        case Element.Og: return "Oganesson";
        default: return "Unknown";
    }
}

struct Atom3D
{
    int aid;
    Element element;
    double x, y, z;

    string name() const
        => element.name;
}

struct Bond3D
{
    int aid1, aid2;
    int order;
}

class Conformer3D
{
package:
    this() { }

public:
    int cid;
    string id;
    Atom3D[] atoms;
    Bond3D[] bonds;
    int[int] aidToIndex;

    double energy;
    double volume;
    double selfOverlap;
    double[] multipoles;

    bool isValid() const
        => atoms.length > 0;

    int indexOf(int aid)
        => aid in aidToIndex ? aidToIndex[aid] : -1;
}