// Builds slides/P11_Energy_Presentation.pptx
// Run:  cd slides && npm install && node build_slides.js
// Charts and logo come from ../charts and ../report/figures, so build those first.

const path = require("path");
const pptxgen = require("pptxgenjs");
// Optional helper that writes THEME's colours into the .pptx theme. Point PPTX_SKILL at the
// folder that has scripts/apply_theme.js; without it the deck still builds, but PowerPoint's
// stock theme colours replace ours.
let applyTheme = null;
try {
  applyTheme = require(path.join(process.env.PPTX_SKILL || "", "scripts/apply_theme.js")).applyTheme;
} catch (e) {
  console.warn("apply_theme.js not found (set PPTX_SKILL); building without the custom theme colours");
}

const ROOT = path.resolve(__dirname, "..");
const CH = (f) => path.join(ROOT, "charts", f);
const LOGO = path.join(ROOT, "report", "figures", "mitaoe_logo.png");
const OUT = path.join(__dirname, "P11_Energy_Presentation.pptx");

// ---------------------------------------------------------------- theme
const THEME = {
  name: "P11 Energy",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1F2A36",     // slate: dark slides, main text
    lt1: "FFFFFF",
    dk2: "3C4A58",     // softer text
    lt2: "EEF2F3",     // card fill
    accent1: "17807F", // wind teal
    accent2: "D98A1C", // solar amber
    accent3: "6B7785", // muted grey
    accent4: "B8482F", // rust, for problems
    accent5: "A9D3D2", // light teal
    accent6: "F6DFB5", // light amber
    hlink: "17807F",
    folHlink: "6B7785",
  },
};
const HEX = THEME.colors;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.333 x 7.5 in
pres.title = "P11: Electricity Load and Renewable Energy in Europe";
pres.author = "Sakshi Deshmukh, Vaishnavi Bhosale, Snehal Mane, Krishna Mungase";
pres.subject = "Big Data Analytics project, MIT Academy of Engineering";
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
const C = pres.SchemeColor;

const W = 13.333, H = 7.5, MX = 0.6;

// ---------------------------------------------------------------- layouts
pres.defineSlideMaster({
  title: "TITLE",
  background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: MX, y: 2.2, w: 8.6, h: 1.9,
        fontFace: THEME.headFontFace, fontSize: 38, bold: true, color: C.text1, valign: "top", align: "left", margin: 0 },
      text: "Title" } },
  ],
});

pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background1 },
  margin: [0.5, 0.6, 0.6, 0.6],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: MX, y: 0.35, w: W - 2 * MX, h: 0.8,
        fontFace: THEME.headFontFace, fontSize: 30, bold: true, color: C.text1, valign: "middle", align: "left", margin: 0 },
      text: "Title" } },
    { text: { text: "P11 · Electricity load and renewable energy in Europe",
        options: { x: MX, y: H - 0.45, w: 8, h: 0.3, fontSize: 10, color: C.accent3, margin: 0 } } },
  ],
  slideNumber: { x: W - MX - 0.6, y: H - 0.45, w: 0.6, h: 0.3, fontSize: 10, color: C.accent3, align: "right" },
});

pres.defineSlideMaster({
  title: "DARK",
  background: { color: C.text1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: MX, y: 0.9, w: W - 2 * MX, h: 1.0,
        fontFace: THEME.headFontFace, fontSize: 34, bold: true, color: C.background1, valign: "middle", align: "left", margin: 0 },
      text: "Title" } },
  ],
});

// ---------------------------------------------------------------- helpers
let objN = 0;
const nm = (s) => `${s}-${++objN}`;

function card(slide, x, y, w, h, fill = C.background2) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.08,
    fill: { color: fill }, line: { color: fill, width: 0 }, objectName: nm("card") });
}
function text(slide, t, o) {
  slide.addText(t, Object.assign({ isTextBox: true, margin: 0, fontSize: 15, color: C.text2,
    valign: "top", objectName: nm("text") }, o));
}
function stat(slide, x, y, w, num, label, color = C.accent1, numSize = 40) {
  text(slide, num, { x, y, w, h: 0.75, fontFace: THEME.headFontFace, fontSize: numSize, bold: true, color });
  text(slide, label, { x, y: y + 0.8, w, h: 0.7, fontSize: 13, color: C.text2 });
}
function numberedCircle(slide, x, y, n, fill = C.accent1) {
  slide.addShape(pres.shapes.OVAL, { x, y, w: 0.5, h: 0.5, fill: { color: fill }, line: { color: fill, width: 0 },
    objectName: nm("circle") });
  text(slide, String(n), { x, y, w: 0.5, h: 0.5, align: "center", valign: "middle", fontSize: 16, bold: true,
    color: C.background1 });
}
// fit an image of pixel size (pw, ph) into a box, keeping its shape
function image(slide, file, pw, ph, x, y, maxW, maxH, alt) {
  let w = maxW, h = (maxW * ph) / pw;
  if (h > maxH) { h = maxH; w = (maxH * pw) / ph; }
  slide.addImage({ path: file, x: x + (maxW - w) / 2, y, w, h, altText: alt, objectName: nm("image") });
  return { w, h };
}
function takeaway(slide, x, y, w, h, title, body) {
  card(slide, x, y, w, h);
  text(slide, title, { x: x + 0.3, y: y + 0.25, w: w - 0.6, h: 0.45, fontSize: 16, bold: true, color: C.text1 });
  text(slide, body, { x: x + 0.3, y: y + 0.75, w: w - 0.6, h: h - 0.95, fontSize: 14 });
}
const content = (section) => pres.addSlide({ masterName: "CONTENT", sectionTitle: section });

// ================================================================= 1. Title
pres.addSection({ title: "Introduction" });
{
  const s = pres.addSlide({ masterName: "TITLE", sectionTitle: "Introduction" });
  s.addImage({ path: LOGO, x: MX, y: 0.55, w: 3.4, h: 3.4 * 110 / 450, altText: "MIT Academy of Engineering logo",
    objectName: nm("logo") });
  text(s, "BIG DATA ANALYTICS · PROJECT P11", { x: MX, y: 1.7, w: 8, h: 0.35, fontSize: 13, bold: true,
    color: C.accent1, charSpacing: 2 });
  s.addText("Electricity Load and Renewable Energy in Europe", { placeholder: "title" });
  text(s, "Six years of hourly data for 10 countries, analysed with HDFS, Java MapReduce, Pig and Hive",
    { x: MX, y: 4.15, w: 8.4, h: 0.7, fontSize: 18, color: C.text2 });
  // team card on the right
  card(s, 9.6, 1.7, 3.13, 4.5);
  text(s, "Team", { x: 9.9, y: 1.95, w: 2.6, h: 0.4, fontSize: 15, bold: true, color: C.text1 });
  text(s, [
    { text: "Sakshi Deshmukh", options: { bold: true, breakLine: true } },
    { text: "202301040191", options: { color: C.accent3, breakLine: true } },
    { text: "Vaishnavi Bhosale", options: { bold: true, breakLine: true } },
    { text: "202301040118", options: { color: C.accent3, breakLine: true } },
    { text: "Snehal Mane", options: { bold: true, breakLine: true } },
    { text: "202301040076", options: { color: C.accent3, breakLine: true } },
    { text: "Krishna Mungase", options: { bold: true, breakLine: true } },
    { text: "202301040029", options: { color: C.accent3 } },
  ], { x: 9.9, y: 2.45, w: 2.6, h: 2.6, fontSize: 13, paraSpaceAfter: 2 });
  text(s, [{ text: "Guide", options: { bold: true, breakLine: true } }, { text: "Prof. Suvidha Shaha" }],
    { x: 9.9, y: 5.2, w: 2.6, h: 0.8, fontSize: 13 });
  text(s, "Final Year B.Tech Computer Engineering · 2026–27", { x: MX, y: 6.6, w: 8, h: 0.35, fontSize: 12,
    color: C.accent3 });
  s.addNotes("Presenter: Krishna. Introduce the team and the topic in one line: we took real hourly electricity data for ten European countries and answered five questions a grid operator would ask, using only Hadoop tools.");
}

// ================================================================= 2. Problem
{
  const s = content("Introduction");
  s.addText("Five questions a grid operator would ask", { placeholder: "title" });
  const qs = [
    "Which country has the highest renewable share, and how has it changed?",
    "What does the daily load curve look like in summer and in winter?",
    "When does wind peak, and does that line up with demand?",
    "Which hours show the largest changes in load?",
    "How strongly is solar generation related to load?",
  ];
  qs.forEach((q, i) => {
    const y = 1.45 + i * 0.85;
    numberedCircle(s, MX, y, i + 1, i % 2 ? C.accent2 : C.accent1);
    text(s, q, { x: MX + 0.75, y: y + 0.02, w: 6.7, h: 0.5, fontSize: 16, color: C.text1, valign: "middle" });
  });
  text(s, "Renewable share = (solar + wind) / load", { x: MX + 0.75, y: 5.85, w: 6.7, h: 0.4, fontSize: 14,
    italic: true, color: C.accent3 });
  card(s, 8.4, 1.45, 4.33, 4.8);
  text(s, "The dataset", { x: 8.7, y: 1.7, w: 3.8, h: 0.4, fontSize: 16, bold: true, color: C.text1 });
  stat(s, 8.7, 2.2, 1.8, "130 MB", "OPSD hourly file, 300 columns", C.accent1, 30);
  stat(s, 10.6, 2.2, 1.9, "50,401", "hours, Jan 2015 to Sep 2020", C.accent1, 30);
  stat(s, 8.7, 3.85, 1.8, "10", "countries: DE FR ES IT GR BE AT DK CZ PT", C.accent2, 30);
  stat(s, 10.6, 3.85, 1.9, "3", "metrics: load, solar, wind (MW)", C.accent2, 30);
  text(s, "Source: Open Power System Data, Time series 2020-10-06", { x: 8.7, y: 5.55, w: 3.8, h: 0.5,
    fontSize: 11, color: C.accent3 });
  s.addNotes("Presenter: Krishna. The analysis is simple on purpose; the point is to do it end to end on Hadoop. Mention that the data comes from European grid operators via the OPSD project and must be cited.");
}

// ================================================================= 3. Data prep
{
  const s = content("Introduction");
  s.addText("Preparing the data: wide to long, then cleaning", { placeholder: "title" });
  // wide -> long illustration
  card(s, MX, 1.45, 5.9, 2.3);
  text(s, "Wide (source)", { x: MX + 0.3, y: 1.6, w: 5.3, h: 0.35, fontSize: 13, bold: true, color: C.accent3 });
  text(s, "utc_timestamp, DE_load, DE_solar, DE_wind, FR_load, …  (300 columns)",
    { x: MX + 0.3, y: 1.95, w: 5.3, h: 0.4, fontSize: 12, fontFace: "Courier New", color: C.text1 });
  text(s, "Long (one reading per line, no header)", { x: MX + 0.3, y: 2.5, w: 5.3, h: 0.35, fontSize: 13,
    bold: true, color: C.accent1 });
  text(s, "2019-01-01 00:00:00,DE,load,43120.50\n2019-01-01 00:00:00,DE,wind,21340.00",
    { x: MX + 0.3, y: 2.85, w: 5.3, h: 0.7, fontSize: 12, fontFace: "Courier New", color: C.text1 });
  stat(s, MX, 4.1, 2.8, "1,480,855", "readings in the full file (52.9 MB); 2019 sample: 262,011", C.accent1, 32);
  stat(s, MX + 3.1, 4.1, 2.8, "70", "faulty readings removed: spikes and dips found through Pig and Hive output", C.accent4, 32);
  // country changes
  text(s, "We checked every column before using it", { x: 7.0, y: 1.45, w: 5.7, h: 0.4, fontSize: 16, bold: true,
    color: C.text1 });
  const rows = [
    ["Poland → Czechia", "solar empty for 92% of hours"],
    ["Netherlands → Greece", "2019 solar averages 1 MW (broken)"],
    ["Italy 2015 dropped", "wind almost entirely missing"],
    ["France, 158,000 MW", "one-hour spike; highest real hour is 94,492 MW"],
  ];
  rows.forEach(([a, b], i) => {
    const y = 2.0 + i * 0.95;
    card(s, 7.0, y, 5.73, 0.8);
    text(s, a, { x: 7.25, y: y + 0.12, w: 5.3, h: 0.3, fontSize: 15, bold: true, color: C.text1 });
    text(s, b, { x: 7.25, y: y + 0.44, w: 5.3, h: 0.3, fontSize: 13 });
  });
  s.addNotes("Presenter: Krishna. Wide to long makes every line the same shape, so MapReduce, Pig and Hive parse it the same way. The France spike was found because Pig's peak-hour output said 158 GW, almost double the real peak. Our results told us the data was wrong.");
}

// ================================================================= 4. Pipeline
pres.addSection({ title: "Implementation" });
{
  const s = content("Implementation");
  s.addText("One pseudo-distributed Hadoop cluster on a laptop", { placeholder: "title" });
  const box = (x, y, w, t1, t2, fill, dark) => {
    card(s, x, y, w, 1.1, fill);
    text(s, t1, { x: x + 0.2, y: y + 0.18, w: w - 0.4, h: 0.4, fontSize: 16, bold: true, align: "center",
      color: dark ? C.background1 : C.text1 });
    text(s, t2, { x: x + 0.2, y: y + 0.6, w: w - 0.4, h: 0.4, fontSize: 12, align: "center",
      color: dark ? C.background1 : C.text2 });
  };
  const arrow = (x1, y1, x2, y2) => s.addShape(pres.shapes.LINE, { x: x1, y: y1, w: x2 - x1, h: y2 - y1,
    line: { color: HEX.accent3, width: 1.5, endArrowType: "triangle" }, objectName: nm("arrow") });
  box(0.6, 1.6, 2.4, "OPSD CSV", "130 MB, wide", C.background2);
  box(3.5, 1.6, 2.4, "reshape.py", "long CSV, cleaned", C.background2);
  box(6.4, 1.6, 2.4, "HDFS", "/energy/long", C.accent1, true);
  arrow(3.0, 2.15, 3.5, 2.15); arrow(5.9, 2.15, 6.4, 2.15);
  box(3.5, 3.4, 2.4, "MapReduce", "Java, 2 jobs", C.accent6);
  box(6.4, 3.4, 2.4, "Pig", "1 script, 13 jobs", C.accent6);
  box(9.3, 3.4, 2.4, "Hive", "5 tables, 10 queries", C.accent6);
  arrow(7.2, 2.7, 4.7, 3.4); arrow(7.6, 2.7, 7.6, 3.4); arrow(8.0, 2.7, 10.5, 3.4);
  box(6.4, 5.2, 2.4, "results/", "CSV, counters, logs", C.background2);
  arrow(4.7, 4.5, 7.2, 5.2); arrow(7.6, 4.5, 7.6, 5.2); arrow(10.5, 4.5, 8.0, 5.2);
  box(9.3, 5.2, 2.4, "9 charts", "matplotlib", C.background2);
  arrow(8.8, 5.75, 9.3, 5.75);
  text(s, [
    { text: "Hadoop 3.4.2 · Pig 0.18.0 · Hive 4.2.1", options: { bold: true, breakLine: true } },
    { text: "JDK 21, macOS on Apple Silicon, 8 GB RAM. NameNode, DataNode, ResourceManager, NodeManager and JobHistoryServer each run as their own process." },
  ], { x: 9.3, y: 1.55, w: 3.4, h: 1.5, fontSize: 12 });
  text(s, "Everything is scripted and in git: one command per step", { x: 0.6, y: 5.35, w: 5.4, h: 0.8,
    fontSize: 14, italic: true, color: C.accent3 });
  s.addNotes("Presenter: Krishna. Pseudo-distributed means every Hadoop daemon is a separate process, so jobs go through YARN exactly as on a cluster. start-dfs.sh needs SSH to localhost, which is off on our Macs, so we start each daemon with hdfs --daemon start. Show jps in the demo.");
}

// ================================================================= 5. HDFS
{
  const s = content("Implementation");
  s.addText("HDFS: block size and replication", { placeholder: "title" });
  text(s, "Same 52.9 MB file, two block sizes (fsck)", { x: MX, y: 1.45, w: 6.2, h: 0.4, fontSize: 16, bold: true,
    color: C.text1 });
  text(s, "128 MB blocks (default)", { x: MX, y: 2.0, w: 3, h: 0.3, fontSize: 13 });
  s.addShape(pres.shapes.RECTANGLE, { x: MX, y: 2.35, w: 5.9, h: 0.55, fill: { color: C.accent1 },
    line: { color: C.accent1, width: 0 }, objectName: nm("block") });
  text(s, "1 block · 52,895,430 bytes", { x: MX + 0.2, y: 2.35, w: 5.5, h: 0.55, valign: "middle", fontSize: 14,
    color: C.background1, bold: true });
  text(s, "32 MB blocks (-D dfs.blocksize=33554432)", { x: MX, y: 3.15, w: 5, h: 0.3, fontSize: 13 });
  s.addShape(pres.shapes.RECTANGLE, { x: MX, y: 3.5, w: 3.74, h: 0.55, fill: { color: C.accent2 },
    line: { color: C.background1, width: 2 }, objectName: nm("block") });
  s.addShape(pres.shapes.RECTANGLE, { x: MX + 3.78, y: 3.5, w: 2.12, h: 0.55, fill: { color: C.accent2 },
    line: { color: C.background1, width: 2 }, objectName: nm("block") });
  text(s, "33,554,432", { x: MX + 0.2, y: 3.5, w: 3.3, h: 0.55, valign: "middle", fontSize: 14, bold: true,
    color: C.text1 });
  text(s, "19,340,998", { x: MX + 3.9, y: 3.5, w: 1.9, h: 0.55, valign: "middle", fontSize: 14, bold: true,
    color: C.text1 });
  text(s, "1 block → 1 map task; 2 blocks → 2 map tasks. The last block is only as big as the data left.",
    { x: MX, y: 4.3, w: 5.9, h: 0.7, fontSize: 14 });
  text(s, "6 folders under /energy: raw, long/sample, long/full, long/full_32mb, output, warehouse",
    { x: MX, y: 5.2, w: 5.9, h: 0.7, fontSize: 13, color: C.accent3 });
  card(s, 7.1, 1.45, 5.63, 4.6);
  text(s, "setrep 2 on a one-node cluster", { x: 7.4, y: 1.7, w: 5, h: 0.4, fontSize: 16, bold: true,
    color: C.text1 });
  text(s, "Target Replicas is 2 but found 1 live replica(s)\nUnder-replicated blocks:  1 (100.0 %)\nStatus: HEALTHY",
    { x: 7.4, y: 2.25, w: 5.1, h: 1.1, fontSize: 12, fontFace: "Courier New", color: C.accent4 });
  text(s, [
    { text: "HDFS never puts two copies of a block on the same DataNode, and we have one. The second copy has nowhere to go.", options: { breakLine: true } },
    { text: " ", options: { breakLine: true } },
    { text: "Status stays HEALTHY: one full copy exists, nothing is lost. We did not use setrep -w, which would wait forever." },
  ], { x: 7.4, y: 3.55, w: 5.1, h: 2.3, fontSize: 14 });
  s.addNotes("Presenter: Krishna. Likely viva questions: why 128 MB blocks (fewer blocks for the NameNode to track, seek time small compared to read time); does a 1 KB file use 128 MB (no, a block only uses the space of its data); why HEALTHY with under-replication (data not lost).");
}

// ================================================================= 6. MapReduce
{
  const s = content("Implementation");
  s.addText("MapReduce in Java: two jobs, combiner, partitioner, counters", { placeholder: "title" });
  takeaway(s, MX, 1.45, 4.0, 2.2, "Job A: average load per country-year",
    "Mapper emits (country,year) → (sum, count). Combiner adds sums and counts but never divides; the reducer divides once.");
  takeaway(s, MX, 3.85, 4.0, 2.2, "Job B: renewable share per month",
    "Sums and hour counts per metric. Share = (avg solar + avg wind) / avg load, so missing Belgian wind hours do not count as zero.");
  text(s, "What the combiner did (Job A, full data)", { x: 5.0, y: 1.45, w: 4.2, h: 0.4, fontSize: 16, bold: true,
    color: C.text1 });
  stat(s, 5.0, 2.0, 2.0, "494,920", "records into the reducers without a combiner", C.accent3, 30);
  stat(s, 7.2, 2.0, 2.0, "59", "with the combiner", C.accent1, 30);
  stat(s, 5.0, 3.6, 2.0, "12.9 MB", "shuffled without a combiner", C.accent3, 30);
  stat(s, 7.2, 3.6, 2.0, "1.5 KB", "with the combiner", C.accent1, 30);
  text(s, "Output identical with and without; checked against pandas.", { x: 5.0, y: 5.2, w: 4.2, h: 0.6,
    fontSize: 13, italic: true, color: C.accent3 });
  card(s, 9.55, 1.45, 3.18, 4.6);
  text(s, "CountryPartitioner", { x: 9.8, y: 1.65, w: 2.8, h: 0.4, fontSize: 15, bold: true, color: C.text1 });
  text(s, "hashes only the country, so each output file holds whole countries (3 reducers)",
    { x: 9.8, y: 2.05, w: 2.75, h: 0.9, fontSize: 12 });
  s.addTable([
    [{ text: "Reducer", options: { bold: true } }, { text: "Countries", options: { bold: true } }],
    ["0", "BE, GR"], ["1", "CZ, IT"], ["2", "AT, DE, DK, ES, FR, PT"],
  ], { x: 9.8, y: 3.0, w: 2.75, colW: [0.85, 1.9], fontSize: 12, color: C.text1, border: { type: "solid",
    color: HEX.accent5, pt: 0.75 }, objectName: nm("table") });
  text(s, "Counters: BAD_LINES, LOAD/SOLAR/WIND_RECORDS, SKIPPED_OTHER_METRIC", { x: 9.8, y: 4.75, w: 2.75,
    h: 0.9, fontSize: 11, color: C.accent3 });
  s.addNotes("Presenter: Sakshi. Key viva point: a combiner may run 0, 1 or many times, so it must not change the answer. An average of averages is wrong (avg(1,2,3)=2, avg(5)=5, avg(2,5)=3.5, but the true average is 2.75), so we pass (sum, count). The partitioner split is uneven (2, 2, 6) because only 10 keys are hashed: AT = 65*31+84 = 2099, 2099 mod 3 = 2.");
}

// ================================================================= 7. Pig
{
  const s = content("Implementation");
  s.addText("Pig: peak hours and daily generation", { placeholder: "title" });
  text(s, "10 operators used", { x: MX, y: 1.45, w: 6, h: 0.4, fontSize: 16, bold: true, color: C.text1 });
  const ops = ["LOAD", "FILTER", "SPLIT", "FOREACH", "DISTINCT", "GROUP", "ORDER", "LIMIT", "JOIN", "STORE"];
  ops.forEach((o, i) => {
    const x = MX + (i % 5) * 1.22, y = 1.95 + Math.floor(i / 5) * 0.6;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 1.1, h: 0.45, rectRadius: 0.2,
      fill: { color: C.accent1 }, line: { color: C.accent1, width: 0 }, objectName: nm("chip") });
    text(s, o, { x, y, w: 1.1, h: 0.45, align: "center", valign: "middle", fontSize: 12, bold: true,
      color: C.background1 });
  });
  text(s, "Functions: SUM, MAX, AVG, COUNT, SUBSTRING, ToDate, GetHour", { x: MX, y: 3.25, w: 6, h: 0.4,
    fontSize: 13, color: C.accent3 });
  text(s, "Compiled into 13 MapReduce jobs, about 5 minutes", { x: MX, y: 3.7, w: 6, h: 0.4, fontSize: 14 });
  text(s, "Highest-load hour (Pig, UTC)", { x: 7.1, y: 1.45, w: 5.6, h: 0.4, fontSize: 16, bold: true,
    color: C.text1 });
  s.addTable([
    [{ text: "Country", options: { bold: true } }, { text: "Hour", options: { bold: true } },
      { text: "Load (MW)", options: { bold: true, align: "right" } }],
    ["France", "2018-02-28 08:00", { text: "94,492", options: { align: "right" } }],
    ["Germany", "2017-12-13 16:00", { text: "77,549", options: { align: "right" } }],
    ["Italy", "2019-07-25 14:00", { text: "53,824", options: { align: "right" } }],
    ["Spain", "2017-01-18 19:00", { text: "41,015", options: { align: "right" } }],
    ["Czechia", "2018-02-28 08:00", { text: "11,142", options: { align: "right" } }],
  ], { x: 7.1, y: 1.95, w: 5.6, colW: [1.5, 2.5, 1.6], fontSize: 13, color: C.text1,
    border: { type: "solid", color: HEX.accent5, pt: 0.75 }, objectName: nm("table") });
  takeaway(s, 7.1, 4.75, 5.63, 1.35, "This table found our bad data",
    "First run: France 158,000 MW for one hour. We traced it to the source and removed it.");
  image(s, CH("6_pig_daily_share.png"), 1293, 553, MX, 4.2, 6.0, 2.6, "Daily renewable share from Pig");
  s.addNotes("Presenter: Vaishnavi. Pig is lazy: nothing runs until STORE or DUMP, which is why it can merge steps. ORDER needs two jobs (a sampler and the sort). France and Czechia peaked in the same hour, 28 Feb 2018, during a cold wave. The small chart is Pig's daily share for Denmark, Germany and France.");
}

// ================================================================= 8. Hive
{
  const s = content("Implementation");
  s.addText("Hive: five kinds of table, one query engine", { placeholder: "title" });
  s.addTable([
    [{ text: "Table", options: { bold: true } }, { text: "Kind", options: { bold: true } }],
    ["energy_raw_ext", "external, CSV"],
    ["energy_parquet", "managed, Parquet"],
    ["energy_by_year", "managed, ORC, partitioned by year (6)"],
    ["energy_hourly", "load, solar, wind side by side"],
    ["load_changes", "hour-to-hour change with LAG"],
  ], { x: MX, y: 1.45, w: 6.0, colW: [2.2, 3.8], fontSize: 13, color: C.text1,
    border: { type: "solid", color: HEX.accent5, pt: 0.75 }, objectName: nm("table") });
  takeaway(s, MX, 4.25, 6.0, 1.9, "Join with GROUP BY, and RANK",
    "Q1 joins average generation and average load per country-year, then RANK() OVER (PARTITION BY year). Its monthly shares equal MapReduce Job B in all 678 months.");
  s.addChart(pres.charts.BAR, [{ name: "Size on HDFS (MB)", labels: ["CSV", "Parquet", "ORC"],
    values: [52.9, 8.3, 5.6] }], {
    x: 7.0, y: 1.35, w: 5.73, h: 4.0, barDir: "col", chartColors: [HEX.accent3, HEX.accent1, HEX.accent1],
    showTitle: true, title: "Same 1,480,855 rows, size on HDFS (MB)", titleFontSize: 14, titleColor: HEX.dk1,
    titleFontFace: "+mn-lt", showValue: true, dataLabelPosition: "outEnd", dataLabelFontSize: 13,
    dataLabelColor: HEX.dk1, dataLabelFontFace: "+mn-lt", dataLabelFormatCode: "0.0", showLegend: false,
    catAxisLabelColor: HEX.dk2, valAxisLabelColor: HEX.dk2, catAxisLabelFontFace: "+mn-lt",
    valAxisLabelFontFace: "+mn-lt", catAxisLabelFontSize: 13, valAxisLabelFontSize: 11,
    valGridLine: { color: "E3E7EA", size: 0.5 }, catGridLine: { style: "none" }, valAxisMaxVal: 60,
    objectName: nm("chart") });
  text(s, "Parquet: 6.4× smaller; a 3-column query read 6.7 MB instead of 52.9 MB. ORC: 9.5× smaller.",
    { x: 7.0, y: 5.45, w: 5.73, h: 0.7, fontSize: 13 });
  s.addNotes("Presenter: Vaishnavi. External vs managed: DROP of an external table keeps the files, DROP of a managed table deletes them. Hive 4 silently turned our managed tables into external ones (TRANSLATED_TO_EXTERNAL); we switched that off in hive-site.xml. EXPLAIN DEPENDENCY with WHERE year = 2019 reads only the year=2019 partition.");
}

// ================================================================= 9. Q1
pres.addSection({ title: "Results" });
{
  const s = content("Results");
  s.addText("Q1. Denmark leads; Germany grew fastest", { placeholder: "title" });
  image(s, CH("1_share_by_year.png"), 1059, 696, MX, 1.35, 7.4, 5.4, "Renewable share heatmap by country and year");
  stat(s, 8.5, 1.5, 4.2, "43% → 50%", "Denmark, 2015 to 2019; almost all wind", C.accent1, 30);
  stat(s, 8.5, 3.0, 4.2, "23% → 34%", "Germany: wind rose from 8.8 to 14.1 GW", C.accent2, 30);
  takeaway(s, 8.5, 4.6, 4.23, 1.6, "Every country rose except Czechia",
    "France is 9th: most of its power is nuclear, which this share does not count.");
  s.addNotes("Presenter: Snehal. Read the heatmap top to bottom: ranking is stable, everything gets darker to the right. 2020 is January to September only and includes lockdowns, so load was lower. On 16 May 2020 Danish wind and solar made 131% of Danish load; the rest was exported.");
}

// ================================================================= 10. Q2
{
  const s = content("Results");
  s.addText("Q2. Winter has two peaks, summer one", { placeholder: "title" });
  image(s, CH("2_load_curve_summer_winter.png"), 1951, 793, MX, 1.3, W - 2 * MX, 4.5,
    "Daily load curve, winter vs summer, ten countries");
  const notes = [
    ["Winter", "late-morning and evening peaks, 17:00 to 20:00", C.accent1],
    ["Summer", "one broad midday peak", C.accent2],
    ["France −34%", "in summer: electric heating in winter", C.accent4],
  ];
  notes.forEach(([a, b, c], i) => {
    const x = MX + i * 4.1;
    text(s, a, { x, y: 5.95, w: 3.9, h: 0.4, fontSize: 16, bold: true, color: c });
    text(s, b, { x, y: 6.35, w: 3.9, h: 0.4, fontSize: 13 });
  });
  s.addNotes("Presenter: Snehal. Hours are local clock time (converted in Hive). Spain, Greece and Italy use about the same in both seasons because air conditioning replaces heating. Greece's summer midday peak is almost as high as its winter evening peak.");
}

// ================================================================= 11. Q3
{
  const s = content("Results");
  s.addText("Q3. Wind matches demand by season, not by hour", { placeholder: "title" });
  image(s, CH("3a_wind_vs_load_by_month.png"), 1951, 793, MX, 1.3, 8.3, 3.4, "Wind and load by month");
  image(s, CH("3b_wind_vs_load_by_hour.png"), 1951, 793, MX, 4.7, 8.3, 2.25, "Wind and load by hour of day");
  takeaway(s, 9.2, 1.35, 3.53, 2.55, "By season: yes",
    "Wind is strongest Dec–Mar in 9 of 10 countries, like demand. Monthly correlation 0.87–0.96 in BE, CZ, DE, DK, FR.");
  takeaway(s, 9.2, 4.1, 3.53, 2.55, "By hour: no",
    "Wind is weakest around 09:00, load peaks at midday. Exceptions: Greece (summer winds), Denmark and Italy (afternoon wind).");
  s.addNotes("Presenter: Snehal. Both lines are indexed to 100 = their own average, so they share one axis; we avoided a second y-axis on purpose. Greece's August meltemi winds match its summer air-conditioning load.");
}

// ================================================================= 12. Q4
{
  const s = content("Results");
  s.addText("Q4. The morning ramp is the hardest hour", { placeholder: "title" });
  image(s, CH("4a_load_change_by_hour.png"), 1324, 650, MX, 1.3, 7.6, 3.75, "Average hour-to-hour load change heatmap");
  image(s, CH("4b_top_load_changes_by_hour.png"), 1637, 526, MX, 5.1, 7.6, 1.85, "Hours of the 20 largest rises and drops");
  stat(s, 8.6, 1.5, 4.0, "+13.9%", "average rise into 07:00 in Italy; every country peaks 06:00–08:00", C.accent4, 36);
  stat(s, 8.6, 3.1, 4.0, "16 of 20", "largest rises are German Monday mornings (+10,957 MW max)", C.accent2, 36);
  takeaway(s, 8.6, 4.75, 4.13, 1.45, "Computed with LAG()",
    "LAG(load) OVER (PARTITION BY country ORDER BY ts), kept only when the rows are exactly 1 hour apart.");
  s.addNotes("Presenter: Snehal. Red = rising, blue = falling. Drops are gentler and come late in the evening. The first version of this chart was all Spanish one-hour dips: errors in the source data, which we then removed.");
}

// ================================================================= 13. Q5
{
  const s = content("Results");
  s.addText("Q5. Solar is only weakly tied to load", { placeholder: "title" });
  const corr = [["GR", 0.362], ["ES", 0.355], ["IT", 0.323], ["DE", 0.313], ["PT", 0.294], ["DK", 0.239],
    ["AT", 0.212], ["CZ", 0.192], ["BE", 0.121], ["FR", -0.034]];
  s.addChart(pres.charts.BAR, [{ name: "Pearson r", labels: corr.map((c) => c[0]), values: corr.map((c) => c[1]) }], {
    x: MX, y: 1.35, w: 6.6, h: 5.0, barDir: "bar", chartColors: [HEX.accent2], catAxisOrientation: "maxMin",
    catAxisLabelPos: "low",
    showTitle: true, title: "Correlation of hourly solar and load, 2015–2020", titleFontSize: 14,
    titleColor: HEX.dk1, titleFontFace: "+mn-lt", showValue: true, dataLabelPosition: "outEnd",
    dataLabelFontSize: 12, dataLabelColor: HEX.dk1, dataLabelFontFace: "+mn-lt", dataLabelFormatCode: "0.00",
    showLegend: false, catAxisLabelColor: HEX.dk2, valAxisLabelColor: HEX.dk2, catAxisLabelFontFace: "+mn-lt",
    valAxisLabelFontFace: "+mn-lt", catAxisLabelFontSize: 13, valAxisLabelFontSize: 11, valAxisMinVal: -0.1,
    valAxisMaxVal: 0.5, valGridLine: { color: "E3E7EA", size: 0.5 }, catGridLine: { style: "none" },
    objectName: nm("chart") });
  image(s, CH("5a_scatter_solar_load_DE_2019.png"), 851, 650, 7.5, 1.35, 5.2, 3.3, "Germany 2019 solar vs load scatter");
  takeaway(s, 7.5, 4.85, 5.23, 1.5, "In summer: 0.43 to 0.64",
    "Solar is zero at night and low in winter, when load is high. In summer load peaks at midday with the sun.");
  s.addNotes("Presenter: Snehal. France is slightly negative because its highest loads are dark winter evenings. In the German scatter the column at zero is night; the two daylight clouds are weekdays (64.7 GW average) and weekends (50.3 GW).");
}

// ================================================================= 14. Scale test
pres.addSection({ title: "Wrap-up" });
{
  const s = content("Wrap-up");
  s.addText("Scale test: time barely moves, counters scale exactly", { placeholder: "title" });
  s.addTable([
    [{ text: "Job A (avg load)", options: { bold: true } }, { text: "Size", options: { bold: true, align: "right" } },
      { text: "Map tasks", options: { bold: true, align: "right" } },
      { text: "Input records", options: { bold: true, align: "right" } },
      { text: "Time (s)", options: { bold: true, align: "right" } }],
    ["sample (2019)", { text: "9.4 MB", options: { align: "right" } }, { text: "1", options: { align: "right" } },
      { text: "262,011", options: { align: "right" } }, { text: "22.6", options: { align: "right" } }],
    ["full", { text: "52.9 MB", options: { align: "right" } }, { text: "1", options: { align: "right" } },
      { text: "1,480,855", options: { align: "right" } }, { text: "23.3", options: { align: "right" } }],
    ["full, 32 MB blocks", { text: "52.9 MB", options: { align: "right" } }, { text: "2", options: { align: "right" } },
      { text: "1,480,855", options: { align: "right" } }, { text: "28.4", options: { align: "right" } }],
    ["full × 5", { text: "264.5 MB", options: { align: "right" } }, { text: "2", options: { align: "right" } },
      { text: "7,404,275", options: { align: "right" } }, { text: "28.6", options: { align: "right" } }],
  ], { x: MX, y: 1.45, w: 7.4, colW: [2.2, 1.2, 1.2, 1.6, 1.2], fontSize: 14, color: C.text1,
    border: { type: "solid", color: HEX.accent5, pt: 0.75 }, objectName: nm("table") });
  text(s, "Pig: 313 s on the sample, 308 s on full (13 jobs). Hive join: 108 / 98 / 124 s (3 jobs).",
    { x: MX, y: 4.2, w: 7.4, h: 0.6, fontSize: 13, color: C.accent3 });
  stat(s, 8.5, 1.45, 4.2, "28× data, +27% time", "YARN start-up (~20 s per job) outweighs reading tens of MB", C.accent1, 28);
  stat(s, 8.5, 3.15, 4.2, "Exactly 5×", "records on the ×5 file, and identical averages: a free correctness check", C.accent2, 28);
  takeaway(s, MX, 5.0, 12.13, 1.2, "More map tasks were slower here",
    "Two tasks share one laptop's CPU and disk and pay for an extra container. On a real cluster they would run on two machines.");
  s.addNotes("Presenter: Krishna. Viva: why is the full run not 5.7 times slower? Fixed start-up cost. Why did x5 get 2 map tasks and not 3? 264,477,150 bytes is 252 MiB, which fits in two 128 MiB blocks. On the x5 run the combiner ran again while merging spill files: combine input was larger than map output.");
}

// ================================================================= 15. Problems
{
  const s = content("Wrap-up");
  s.addText("What went wrong, and how we fixed it", { placeholder: "title" });
  const probs = [
    ["No SSH to localhost", "start-dfs.sh failed; we start each daemon with --daemon start"],
    ["Missing jar in YARN tasks", "Pig and Hive need commons-collections 3; shipped with every job"],
    ["Managed became external", "Hive 4 default; turned off in hive-site.xml"],
    ["Map join crashed", "local child process lost our settings; reduce-side join instead"],
    ["Only 1 reducer ran", "mapreduce.job.reduces already defaults to 1; own setting"],
    ["Bad source data", "70 readings found through our own results; 3 pipeline re-runs"],
  ];
  probs.forEach(([a, b], i) => {
    const col = i % 3, row = Math.floor(i / 3);
    const x = MX + col * 4.1, y = 1.5 + row * 2.4;
    card(s, x, y, 3.85, 2.15);
    numberedCircle(s, x + 0.3, y + 0.3, i + 1, i === 5 ? C.accent4 : C.accent1);
    text(s, a, { x: x + 0.3, y: y + 0.95, w: 3.3, h: 0.4, fontSize: 15, bold: true, color: C.text1 });
    text(s, b, { x: x + 0.3, y: y + 1.35, w: 3.3, h: 0.7, fontSize: 13 });
  });
  s.addNotes("Presenter: any member. Each problem is written up in the step's doc in the repository. The most useful lesson: unrealistic results (158 GW in France, Spanish one-hour dips) showed us errors in the data that a look at the raw file would have missed.");
}

// ================================================================= 16. Conclusion
{
  const s = pres.addSlide({ masterName: "DARK", sectionTitle: "Wrap-up" });
  s.addText("Conclusion", { placeholder: "title" });
  const pts = [
    ["Every requirement met", "HDFS, 2 Java jobs with combiner + partitioner + counters, 10 Pig operators, 5 kinds of Hive table, 9 charts, scale test"],
    ["Tools agree", "MapReduce, Hive and pandas give the same numbers"],
    ["Answers", "Denmark leads, Germany grew most; wind fits demand by season; morning ramp is hardest; solar weakly tied to load"],
  ];
  pts.forEach(([a, b], i) => {
    const y = 2.2 + i * 1.25;
    text(s, a, { x: MX, y, w: 3.6, h: 0.5, fontSize: 18, bold: true, color: C.accent5 });
    text(s, b, { x: 4.4, y, w: 8.3, h: 1.0, fontSize: 16, color: C.background1 });
  });
  text(s, "github.com/krishmungase/P11-Energy", { x: MX, y: 6.2, w: 8, h: 0.4, fontSize: 16, bold: true,
    color: C.accent6 });
  text(s, "Next: data after 2021, hydro and prices; a multi-node cluster", { x: MX, y: 6.65, w: 10, h: 0.4,
    fontSize: 13, color: C.accent5 });
  s.addNotes("Presenter: Snehal. Close with the repository link: code, results, logs and one documentation page per step. Then invite questions.");
}

// ================================================================= 17. Thanks
{
  const s = pres.addSlide({ masterName: "DARK", sectionTitle: "Wrap-up" });
  s.addText("Thank you", { placeholder: "title" });
  text(s, "Questions?", { x: MX, y: 2.1, w: 8, h: 0.8, fontFace: THEME.headFontFace, fontSize: 28,
    color: C.accent5 });
  text(s, "Sakshi Deshmukh · Vaishnavi Bhosale · Snehal Mane · Krishna Mungase", { x: MX, y: 5.9, w: 12, h: 0.4,
    fontSize: 15, color: C.background1 });
  text(s, "Guide: Prof. Suvidha Shaha · MIT Academy of Engineering, Alandi (D), Pune", { x: MX, y: 6.35, w: 12,
    h: 0.4, fontSize: 13, color: C.accent5 });
  s.addNotes("All members. Likely questions are collected in docs/10-viva.md.");
}

// ---------------------------------------------------------------- write
(async () => {
  await pres.writeFile({ fileName: OUT });
  if (applyTheme) await applyTheme(OUT, THEME);
  console.log("wrote", OUT);
})();
