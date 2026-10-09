// Declarative Tdarr config, applied idempotently through Tdarr's API by the
// tdarr-config CronJob. Tdarr keeps flows, libraries and settings only in its
// own DB; this file is their source of truth (UI edits are reverted).
//
// Policy: lossless cleanup only, never a video re-encode.
//   - remove audio tracks that are not English, unless the title's original
//     language is not English (then all audio is kept)
//   - remove subtitle tracks that are not English (forced tracks stay)
//   - untagged/undetermined tracks always stay; attachments (fonts) stay
//   - only when an English track of that type exists
// Safety: skip hardlinked files (still seeding), non-MKV files (a container
// change would make Radarr/Sonarr see a new file), and files modified in the
// last 24h; replace only if duration is within 1%, size shrank, and the
// source is unchanged since the job started. Errors leave the original.
"use strict"
const fs = require("fs")

const TDARR = process.env.TDARR_URL
const KEY = process.env.TDARR_API_KEY
const CACHE = "/media/.tdarr-cache"
const FOREIGN_LIST = CACHE + "/foreign-originals.txt"
const ARR = {
  radarr: { url: "http://radarr.default.svc.cluster.local:7878", key: process.env.RADARR_API_KEY },
  sonarr: { url: "http://sonarr.default.svc.cluster.local:8989", key: process.env.SONARR_API_KEY },
}
// Processing window, local time (TZ=Asia/Dubai): 01:00-07:00 every day.
const WINDOW_HOURS = [1, 2, 3, 4, 5, 6]

const log = (m) => console.log(new Date().toISOString() + " " + m)
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

async function api(endpoint, data) {
  const res = await fetch(TDARR + "/api/v2/" + endpoint, {
    method: data === undefined ? "GET" : "POST",
    headers: { "Content-Type": "application/json", "x-api-key": KEY },
    body: data === undefined ? undefined : JSON.stringify({ data }),
    signal: AbortSignal.timeout(60000),
  })
  if (!res.ok) throw new Error(endpoint + " HTTP " + res.status + " " + (await res.text()).slice(0, 200))
  const text = await res.text()
  try { return JSON.parse(text) } catch (e) { return text }
}
const db = (collection, mode, extra) => api("cruddb", Object.assign({ collection, mode }, extra || {}))

async function arr(kind, endpoint) {
  const a = ARR[kind]
  const res = await fetch(a.url + "/api/v3/" + endpoint, { headers: { "X-Api-Key": a.key }, signal: AbortSignal.timeout(60000) })
  if (!res.ok) throw new Error(kind + " " + endpoint + " HTTP " + res.status)
  return res.json()
}

// ---------------------------------------------------------------- flow code
const GUARD = String.raw`
module.exports = async (args) => {
  const fs = require('fs');
  const file = args.inputFileObj._id;
  const skip = (why) => { args.jobLog('skip: ' + why); return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables }; };
  const streams = (args.inputFileObj.ffProbeData && args.inputFileObj.ffProbeData.streams) || [];
  if (!streams.some((s) => s.codec_type === 'video')) return skip('no video stream');
  // ffmpeg cannot stream-copy a track whose codec it does not recognise (e.g. some
  // streaming-service subtitle formats probe as "unknown"); muxing would fail.
  const unknown = streams.filter((s) => ['video', 'audio', 'subtitle'].includes(s.codec_type) && (!s.codec_name || s.codec_name === 'unknown'));
  if (unknown.length) return skip('track(s) ffmpeg cannot copy: ' + unknown.map((s) => s.codec_type + '#' + s.index).join(', '));
  if (!/\.mkv$/i.test(file)) return skip('not an MKV (a container change would look like a new file to Radarr/Sonarr)');
  let st;
  try { st = fs.statSync(file); } catch (e) { return skip('cannot stat file'); }
  if (st.nlink > 1) return skip('hardlinked (' + st.nlink + ' links, still seeding)');
  if (Date.now() - st.mtimeMs < 24 * 3600 * 1000) return skip('modified in the last 24h');
  let list;
  try { list = fs.readFileSync('/media/.tdarr-cache/foreign-originals.txt', 'utf8'); } catch (e) { return skip('original-language list missing (fail safe)'); }
  const u = (args.variables.user = args.variables.user || {});
  u.gbForeign = list.split('\n').map((x) => x.trim()).filter(Boolean).some((p) => file.startsWith(p)) ? '1' : '0';
  u.gbSize = String(st.size);
  u.gbMtime = String(Math.floor(st.mtimeMs));
  return { outputFileObj: args.inputFileObj, outputNumber: 1, variables: args.variables };
};
`

const STRIP = String.raw`
module.exports = async (args) => {
  const cmd = args.variables.ffmpegCommand;
  const u = args.variables.user || {};
  const lang = (s) => ((s.tags && s.tags.language) || '').trim().toLowerCase();
  const isEng = (s) => /^en/.test(lang(s));
  const isUnd = (s) => ['', 'und', 'unk', 'zxx', 'mis'].includes(lang(s));
  const removed = [];
  const strip = (type) => {
    const set = cmd.streams.filter((s) => s.codec_type === type && !s.removed);
    if (!set.some(isEng)) return; // no English track of this type: keep everything
    for (const s of set) {
      if (isEng(s) || isUnd(s)) continue;
      if (type === 'subtitle' && s.disposition && s.disposition.forced) continue;
      s.removed = true;
      removed.push(type + ':' + lang(s));
    }
  };
  if (u.gbForeign === '1') args.jobLog('original language is not English: keeping all audio');
  else strip('audio');
  strip('subtitle');
  if (removed.length === 0) {
    args.jobLog('nothing to remove');
    return { outputFileObj: args.inputFileObj, outputNumber: 2, variables: args.variables };
  }
  cmd.shouldProcess = true;
  args.jobLog('removing ' + removed.length + ' stream(s): ' + removed.join(', '));
  return { outputFileObj: args.inputFileObj, outputNumber: 1, variables: args.variables };
};
`

const UNCHANGED = String.raw`
module.exports = async (args) => {
  const fs = require('fs');
  const u = args.variables.user || {};
  let ok = false;
  try {
    const st = fs.statSync(args.originalLibraryFile._id);
    ok = String(st.size) === u.gbSize && String(Math.floor(st.mtimeMs)) === u.gbMtime;
  } catch (e) {}
  args.jobLog(ok ? 'source unchanged: safe to replace' : 'source changed or missing since the job started: not replacing');
  return { outputFileObj: args.inputFileObj, outputNumber: ok ? 1 : 2, variables: args.variables };
};
`

function buildFlow(id, name, arrKind) {
  const flowPlugins = []
  const flowEdges = []
  const node = (nid, pluginName, label, inputsDB, x, y) =>
    flowPlugins.push({ name: label, sourceRepo: "Community", pluginName, version: "1.0.0", id: nid,
      position: { x, y }, fpEnabled: true, inputsDB: inputsDB || {} })
  const edge = (source, target, sourceHandle) =>
    flowEdges.push({ source, sourceHandle: sourceHandle || "1", target, targetHandle: null, id: "e" + (flowEdges.length + 1) })

  node("in", "inputFile", "Input", {}, 400, 0)
  node("guard", "customFunction", "Skip rules (hardlink, non-MKV, recent, list missing)", { code: GUARD }, 400, 100)
  node("skip", "comment", "Skipped: file untouched", {}, 800, 150)
  node("start", "ffmpegCommandStart", "Begin ffmpeg command (stream copy)", {}, 400, 200)
  node("strip", "customFunction", "Pick non-English tracks to remove", { code: STRIP }, 400, 300)
  node("cont", "ffmpegCommandSetContainer", "MKV", { container: "mkv", forceConform: "false" }, 400, 400)
  node("exec", "ffmpegCommandExecute", "Run ffmpeg (copy only)", {}, 400, 500)
  node("dur", "compareFileDurationRatio", "Duration within 1%", { greaterThan: "99", lessThan: "101" }, 400, 600)
  node("size", "compareFileSizeRatio", "Smaller than original", { greaterThan: "20", lessThan: "100" }, 400, 700)
  node("review", "requireReview", "Needs review: original untouched", {}, 800, 650)
  node("unchanged", "customFunction", "Source unchanged since start?", { code: UNCHANGED }, 400, 800)
  node("replace", "replaceOriginalFile", "Replace original", {}, 400, 900)
  if (arrKind)
    node("notify", "notifyRadarrOrSonarr", "Tell " + arrKind + " to rescan",
      { arr: arrKind, arr_api_key: ARR[arrKind].key, arr_host: ARR[arrKind].url }, 400, 1000)
  node("onerr", "onFlowError", "On error", {}, 1200, 100)
  node("fail", "failFlow", "Fail: original untouched", {}, 1200, 200)

  edge("in", "guard")
  edge("guard", "start", "1")
  edge("guard", "skip", "2")
  edge("start", "strip")
  edge("strip", "cont", "1")
  edge("strip", "skip", "2")
  edge("cont", "exec")
  edge("exec", "dur")
  edge("dur", "size", "1")
  edge("dur", "review", "2")
  edge("dur", "review", "3")
  edge("size", "unchanged", "1")
  edge("size", "review", "2")
  edge("size", "review", "3")
  edge("unchanged", "replace", "1")
  edge("unchanged", "review", "2")
  if (arrKind) edge("replace", "notify")
  edge("onerr", "fail")
  return { _id: id, name, description: "Lossless: drop non-English audio/subtitles (stream copy, never re-encodes). Managed by tdarr-config.",
    tags: "", flowPlugins, flowEdges }
}

const FLOWS = [
  buildFlow("grappleberryLosslessMovies", "Lossless cleanup (movies)", "radarr"),
  buildFlow("grappleberryLosslessTv", "Lossless cleanup (TV)", "sonarr"),
  buildFlow("grappleberryLosslessTest", "Lossless cleanup (test, no rescan)", null),
]

// ------------------------------------------------------------- libraries
function schedule(allHours) {
  const out = []
  for (const day of ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
    for (let h = 0; h < 24; h += 1) {
      const p = (n) => String(n).padStart(2, "0")
      out.push({ _id: day + ":" + p(h) + "-" + p(h + 1), checked: allHours || WINDOW_HOURS.includes(h) })
    }
  return out
}

function library(id, name, folder, flowId, priority, allHours, enabled) {
  return {
    _id: id, name, folder, cache: CACHE, output: ".", container: ".mkv",
    folderWatching: false, useFsEvents: false, processLibrary: enabled, scanOnStart: false,
    scheduledScanFindNew: true, folderWatchScanInterval: 30, scannerThreadCount: 1,
    pluginCommunity: true, pluginIDs: [], schedule: schedule(allHours), priority,
    foldersToIgnore: "", containerFilter: "mkv", folderToFolderConversion: false,
    copyIfConditionsMet: false, handbrake: false, ffmpeg: true, handbrakescan: false,
    ffmpegscan: true, exifToolScan: false, mediaInfoScan: false, closedCaptionScan: false,
    expanded: false, scanButtons: false, verboseLogs: false,
    decisionMaker: { settingsPlugin: false, settingsFlows: true, settingsVideo: false },
    processTranscodes: true, processHealthChecks: false, holdNewFiles: false,
    pluginStackOverview: false, processPluginsSequentially: true, flowId,
  }
}

// The real libraries stay disabled until the flow has been checked on copies
// in the test library; flip LIBRARIES_ENABLED to start processing them.
const LIBRARIES_ENABLED = false
const LIBRARIES = [
  library("grappleberryMovies", "Movies", "/media/main/movies", "grappleberryLosslessMovies", 1, false, LIBRARIES_ENABLED),
  library("grappleberryTv", "TV Shows", "/media/main/tv", "grappleberryLosslessTv", 2, false, LIBRARIES_ENABLED),
  library("grappleberryKidsMovies", "Kids Movies", "/media/kids/movies", "grappleberryLosslessMovies", 3, false, LIBRARIES_ENABLED),
  library("grappleberryKidsTv", "Kids TV Shows", "/media/kids/tv", "grappleberryLosslessTv", 4, false, LIBRARIES_ENABLED),
  // Copies only, outside every Plex/arr library: for checking the flow on
  // a real file before it touches the library. Runs at any hour.
  library("grappleberryTest", "Test (copies)", "/media/.tdarr-test", "grappleberryLosslessTest", 0, true, true),
]

// ------------------------------------------------------------------ sync
async function syncSettings() {
  const want = { runMkvpropedit: false }
  const have = (await db("SettingsGlobalJSONDB", "getAll"))[0]
  const diff = Object.entries(want).filter(([k, v]) => !same(have[k], v))
  if (!diff.length) return log("settings: unchanged")
  await db("SettingsGlobalJSONDB", "update", { docID: have._id, obj: Object.fromEntries(diff) })
  log("settings: updated " + diff.map(([k]) => k).join(", "))
}

async function syncDocs(collection, desired, keys) {
  const existing = new Map((await db(collection, "getAll")).map((d) => [d._id, d]))
  for (const want of desired) {
    const have = existing.get(want._id)
    const pick = (d) => Object.fromEntries(keys(want).map((k) => [k, d[k]]))
    if (!have) {
      await db(collection, "insert", { docID: want._id, obj: Object.assign({ createdAt: Date.now() }, want) })
      log(collection + " " + want._id + ": created")
    } else if (!same(pick(have), pick(want))) {
      await db(collection, "update", { docID: want._id, obj: want })
      log(collection + " " + want._id + ": updated")
    } else log(collection + " " + want._id + ": unchanged")
  }
}

// Path prefixes of titles whose original language is not English: their
// audio is never stripped. Written to the NFS cache every node reads.
async function syncForeignOriginals() {
  const movies = await arr("radarr", "movie")
  const series = await arr("sonarr", "series")
  const foreign = [...movies, ...series]
    .filter((t) => t.path && t.originalLanguage && t.originalLanguage.name && t.originalLanguage.name !== "English")
    .map((t) => t.path.replace(/\/?$/, "/"))
    .sort()
  const text = foreign.join("\n") + "\n"
  const old = fs.existsSync(FOREIGN_LIST) ? fs.readFileSync(FOREIGN_LIST, "utf8") : null
  if (old !== text) {
    fs.writeFileSync(FOREIGN_LIST + ".tmp", text)
    fs.renameSync(FOREIGN_LIST + ".tmp", FOREIGN_LIST)
    log("foreign-originals: " + foreign.length + " titles written")
  } else log("foreign-originals: unchanged (" + foreign.length + " titles)")
}

async function main() {
  for (let i = 0; ; i += 1) {
    try { await api("get-nodes"); break } catch (e) {
      if (i >= 30) throw new Error("Tdarr API unreachable: " + e.message)
      await new Promise((r) => setTimeout(r, 10000))
    }
  }
  fs.mkdirSync(CACHE, { recursive: true })
  fs.mkdirSync("/media/.tdarr-test", { recursive: true })
  await syncForeignOriginals()
  await syncSettings()
  await syncDocs("FlowsJSONDB", FLOWS, () => ["name", "description", "flowPlugins", "flowEdges"])
  await syncDocs("LibrarySettingsJSONDB", LIBRARIES, (w) => Object.keys(w).filter((k) => k !== "_id"))
  log("done")
}

main().catch((e) => { console.error(e.stack || String(e)); process.exit(1) })
