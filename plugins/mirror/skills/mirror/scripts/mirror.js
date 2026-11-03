/* Local-only Mirror launcher. osascript JavaScript + macOS Foundation/AppKit. */
ObjC.import("Foundation");
ObjC.import("AppKit");
ObjC.import("stdlib");

var MirrorHelper = (function () {
    "use strict";
    var bundleID = "local.mirror.companion";

    function failure(code, message) {
        var error = new Error(message);
        error.mirrorCode = code;
        throw error;
    }

    function validID(value, label, maximum, pattern) {
        if (typeof value !== "string" || value.length > maximum || !pattern.test(value) || value.indexOf("..") >= 0) {
            failure("invalid_arguments", label + " must use letters, digits, _, - and . within its identifier length limit; '..' is not allowed.");
        }
        return value;
    }

    function utf8Length(value) {
        try { return encodeURIComponent(value).replace(/%[0-9A-F]{2}/g, "x").length; }
        catch (_) { failure("invalid_arguments", "Query must contain valid Unicode."); }
    }

    function hasControlCharacters(value) {
        return $(value).rangeOfCharacterFromSet($.NSCharacterSet.controlCharacterSet).location !== $.NSNotFound;
    }

    var actions = ["status", "list", "open", "duplicate", "close", "hide", "show", "refresh", "cancel", "copy", "find", "font", "frame", "bind", "unbind"];
    var uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    function parse(argv) {
        if (!argv.length || argv[0] === "--help" || argv[0] === "help") {
            if (argv.length > 1) failure("invalid_arguments", "Help takes no options.");
            return { command: "help" };
        }
        if (actions.indexOf(argv[0]) < 0) failure("invalid_arguments", "Unknown command. See --help.");
        var result = { command: argv[0] };
        var flags = { "--app": "app", "--launch": "launch", "--conversation": "conversationID", "--message": "messageID", "--window": "windowID",
            "--revision": "expectedRevision", "--request-id": "requestID", "--new": "newWindow", "--query": "query", "--font-size": "fontSize", "--frame": "frame" };
        for (var i = 1; i < argv.length; i += 2) {
            var key = Object.prototype.hasOwnProperty.call(flags, argv[i]) ? flags[argv[i]] : null;
            if (!key || i + 1 >= argv.length || result[key] !== undefined) failure("invalid_arguments", "Unknown, duplicated, or incomplete option. See --help.");
            result[key] = argv[i + 1];
        }
        if (result.app !== undefined && (result.app[0] !== "/" || !/\.app\/?$/.test(result.app) || /[\x00-\x1f\x7f-\x9f]/.test(result.app))) {
            failure("invalid_arguments", "--app must be an absolute path to a Mirror application bundle (.app).");
        }
        var reading = result.command === "status" || result.command === "list";
        var allowed = ["command", "app", "requestID"];
        if (!reading) allowed.push("expectedRevision", "windowID");
        else allowed.push("launch");
        if (result.command === "open") allowed.push("conversationID", "messageID", "newWindow");
        if (result.command === "find") allowed.push("query");
        if (result.command === "font") allowed.push("fontSize");
        if (result.command === "frame") allowed.push("frame");
        Object.keys(result).forEach(function (key) { if (allowed.indexOf(key) < 0) failure("invalid_arguments", "Option is not supported for this command."); });
        if (result.launch !== undefined) {
            if (result.launch !== "true" && result.launch !== "false") failure("invalid_arguments", "--launch must be true or false.");
            result.launch = result.launch === "true";
        }
        if (!reading) {
            if (!/^(0|[1-9]\d{0,15})$/.test(result.expectedRevision || "")) failure("invalid_arguments", "Every change requires --revision from a fresh status response.");
            result.expectedRevision = Number(result.expectedRevision);
            if (result.expectedRevision > 9007199254740991) failure("invalid_arguments", "Invalid revision.");
        }
        ["windowID", "requestID"].forEach(function (key) {
            if (result[key] !== undefined && !uuidPattern.test(result[key])) failure("invalid_arguments", key + " must be a UUID.");
        });
        if (!reading && result.command !== "open" && result.windowID === undefined) failure("invalid_arguments", "This command requires --window from status or list.");
        if (result.command === "open") {
            validID(result.conversationID, "Conversation", 256, /^[A-Za-z0-9_.-]+$/);
            if (result.messageID !== undefined) {
                validID(result.messageID, "Message", 512, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/);
                if (!/^[^/]+\/[^/]+$/.test(result.messageID)) failure("invalid_arguments", "--message must be TURN_ID/ITEM_ID.");
            }
            if (result.newWindow !== undefined) {
                if (result.newWindow !== "true" && result.newWindow !== "false") failure("invalid_arguments", "--new must be true or false.");
                result.newWindow = result.newWindow === "true";
                if (result.newWindow && result.windowID) failure("invalid_arguments", "--new true cannot select an existing --window.");
            }
        }
        if (result.command === "find") {
            if (typeof result.query !== "string" || utf8Length(result.query) > 4096 || hasControlCharacters(result.query)) failure("invalid_arguments", "find requires --query (up to 4096 UTF-8 bytes, no control characters); an empty string clears find.");
        }
        if (result.command === "font") {
            if (!/^(?:\d+)(?:\.\d+)?$/.test(result.fontSize || "")) failure("invalid_arguments", "font requires --font-size between 11 and 26.");
            result.fontSize = Number(result.fontSize);
            if (result.fontSize < 11 || result.fontSize > 26) failure("invalid_arguments", "Font size must be between 11 and 26.");
        }
        if (result.command === "frame") {
            try { result.frame = JSON.parse(result.frame); } catch (_) { failure("invalid_arguments", "frame requires --frame JSON with x, y, width and height."); }
            if (!result.frame || Array.isArray(result.frame) || Object.keys(result.frame).sort().join(",") !== "height,width,x,y") failure("invalid_arguments", "Frame must contain exactly x, y, width and height.");
            ["x", "y", "width", "height"].forEach(function (key) {
                var value = result.frame[key];
                if (typeof value !== "number" || !isFinite(value) || Math.abs(value) > 100000) failure("invalid_arguments", "Frame values must be finite screen coordinates.");
            });
            if (result.frame.width < 280 || result.frame.height < 260) failure("invalid_arguments", "Frame dimensions must be at least 280 by 260.");
        }
        return result;
    }

    function commandRequest(options, runtime) {
        var request = { requestID: options.requestID || runtime.uuid(), action: options.command };
        ["expectedRevision", "windowID", "conversationID", "messageID", "newWindow", "query", "fontSize", "frame"].forEach(function (key) {
            if (options[key] !== undefined) request[key] = options[key];
        });
        return request;
    }

    function decodeBase64(text) {
        var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var output = [], bits = 0, value = 0;
        for (var i = 0; i < text.length && text[i] !== "="; i++) {
            var digit = alphabet.indexOf(text[i]);
            if (digit < 0) continue;
            value = (value << 6) | digit;
            bits += 6;
            if (bits >= 8) { bits -= 8; output.push((value >> bits) & 255); }
        }
        return output;
    }

    function arm64Executable(bytes) {
        function u32(offset, little) {
            if (offset + 4 > bytes.length) return -1;
            var b = bytes.slice(offset, offset + 4);
            if (little) b.reverse();
            return (b[0] * 16777216 + b[1] * 65536 + b[2] * 256 + b[3]);
        }
        var magic = u32(0, false);
        if (magic === 0xcffaedfe) return u32(4, true) === 0x0100000c && u32(12, true) === 2;
        if (magic === 0xfeedfacf) return u32(4, false) === 0x0100000c && u32(12, false) === 2;
        var little = magic === 0xbebafeca || magic === 0xbfbafeca;
        if (magic !== 0xcafebabe && magic !== 0xcafebabf && !little) return false;
        var count = u32(4, little), stride = (magic === 0xcafebabf || magic === 0xbfbafeca) ? 32 : 20;
        if (count < 1 || count > 64 || 8 + count * stride > bytes.length) return false;
        for (var i = 0; i < count; i++) {
            if (u32(8 + i * stride, little) === 0x0100000c) return true;
        }
        return false;
    }

    function versionAtLeast(actual, required) {
        var a = actual.split("."), b = required.split(".");
        for (var i = 0; i < Math.max(a.length, b.length); i++) {
            var av = Number(a[i] || 0), bv = Number(b[i] || 0);
            if (av !== bv) return av > bv;
        }
        return true;
    }

    function validateMetadata(info, systemVersion) {
        if (!info || info.CFBundleIdentifier !== bundleID || info.CFBundlePackageType !== "APPL" || info.CFBundleExecutable !== "Mirror") {
            failure("invalid_app", "The selected app is not a supported Mirror application bundle.");
        }
        var appVersion = info.CFBundleShortVersionString;
        if (typeof appVersion !== "string" || !/^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$/.test(appVersion)) {
            failure("invalid_app", "The selected Mirror app has no valid three-part release version.");
        }
        if (!versionAtLeast(appVersion, "1.0.0")) {
            failure("unsupported_app_version", "This plugin requires Mirror 1.0.0 or later. Select an updated Mirror application.");
        }
        var minimum = info.LSMinimumSystemVersion;
        if (typeof minimum !== "string" || !/^\d+(\.\d+){0,2}$/.test(minimum)) {
            failure("invalid_app", "The selected Mirror app has invalid platform metadata.");
        }
        if (!versionAtLeast(systemVersion, minimum)) {
            failure("unsupported_app_version", "The selected Mirror app requires a newer version of macOS.");
        }
    }

    function inspectApp(path, systemVersion) {
        var fm = $.NSFileManager.defaultManager;
        path = ObjC.unwrap($(path).stringByStandardizingPath.stringByResolvingSymlinksInPath);
        var info = $.NSDictionary.dictionaryWithContentsOfFile($(path + "/Contents/Info.plist"));
        if (!info || info.isNil()) failure("invalid_app", "The selected app has no readable application metadata.");
        var metadata = ObjC.deepUnwrap(info);
        validateMetadata(metadata, systemVersion);
        var executable = path + "/Contents/MacOS/Mirror";
        if (!fm.isExecutableFileAtPath($(executable))) failure("invalid_app", "The selected Mirror app has no runnable executable.");
        var handle = $.NSFileHandle.fileHandleForReadingAtPath($(executable));
        if (!handle || handle.isNil()) failure("invalid_app", "The selected Mirror executable could not be read.");
        var bytes;
        try { bytes = decodeBase64(ObjC.unwrap(handle.readDataOfLength(4096).base64EncodedStringWithOptions(0))); }
        finally { handle.closeFile; }
        if (!arm64Executable(bytes)) failure("invalid_app", "The selected Mirror app does not contain an Apple Silicon executable.");
        return { path: path, version: metadata.CFBundleShortVersionString };
    }

    function findApp(options, runtime) {
        if (options.app !== undefined) return runtime.inspect(options.app);
        var running = runtime.runningAppPaths(), uniqueRunning = [];
        for (var r = 0; r < running.length; r++) {
            if (uniqueRunning.indexOf(running[r]) < 0) uniqueRunning.push(running[r]);
        }
        if (uniqueRunning.length > 1) {
            failure("ambiguous_app", "Multiple Mirror application copies are running. Choose the intended one with --app and its absolute .app path.");
        }
        // Do not silently open a second copy when the running one is incompatible.
        if (uniqueRunning.length === 1) return runtime.inspect(uniqueRunning[0]);
        var candidates = ["/Applications/Mirror.app", runtime.home + "/Applications/Mirror.app"];
        var invalid = false, compatible = [];
        for (var i = 0; i < candidates.length; i++) {
            if (!runtime.exists(candidates[i])) continue;
            try {
                var app = runtime.inspect(candidates[i]);
                if (!compatible.some(function (found) { return found.path === app.path; })) compatible.push(app);
            }
            catch (error) {
                if (!error.mirrorCode) throw error;
                invalid = true;
            }
        }
        if (compatible.length > 1) {
            failure("ambiguous_app", "Multiple compatible Mirror applications are installed. Choose the intended one with --app and its absolute .app path.");
        }
        if (compatible.length === 1) return compatible[0];
        if (invalid) failure("invalid_app", "A Mirror app was found but is not compatible. Select a valid bundle with --app.");
        failure("app_not_found", "Open your existing Mirror app, install Mirror in /Applications or ~/Applications, or pass --app with its absolute .app path.");
    }

    function execute(options, runtime) {
        if (options.command === "help") return {
            ok: true, status: "help", usage: [
                "mirror.sh status|list [--launch false] [--app /absolute/path/Mirror.app]",
                "mirror.sh open --conversation ID [--message TURN_ID/ITEM_ID] [--window UUID | --new true] --revision N",
                "mirror.sh duplicate|close|hide|show|refresh|cancel|copy|bind|unbind --window UUID --revision N",
                "mirror.sh find --window UUID --query TEXT --revision N",
                "mirror.sh font --window UUID --font-size 11..26 --revision N",
                "mirror.sh frame --window UUID --frame '{\"x\":0,\"y\":0,\"width\":500,\"height\":700}' --revision N"
            ], note: "All commands accept --app and --request-id UUID. Requires Mirror 1.0.0+. Human actions take priority: stop on revision_conflict or agent_paused. Never retry a timed-out mutation blindly."
        };
        options.requestID = options.requestID || runtime.uuid();
        var app = findApp(options, runtime);
        if (!versionAtLeast(app.version, "1.0.0")) failure("upgrade_required", "Agent window controls require Mirror 1.0.0 or later. This app has not been launched or changed.");
        var reading = options.command === "status" || options.command === "list";
        var running = runtime.isRunning(app.path), launched = false;
        if (!running) {
            if (!reading || options.launch === false) failure("app_not_running", "Mirror is not running. No launch was attempted; respect a human close or quit action.");
            runtime.open(["-g", "-a", app.path, "--args", "--agent-launch"]);
            launched = true;
        }
        var request = commandRequest(options, runtime);
        var result = runtime.command(app.path, request);
        if (!result || typeof result.ok !== "boolean" || typeof result.status !== "string") failure("invalid_response", "Mirror returned an invalid command response.");
        // Startup retries are read-only. A mutating command is sent exactly once.
        for (var attempt = 0; launched && result.status === "service_unavailable" && attempt < 10; attempt++) {
            runtime.sleep(0.2);
            result = runtime.command(app.path, request);
        }
        if (result.status === "service_unavailable") {
            return { ok: false, status: launched ? "startup_pending" : "restart_required", requestID: request.requestID,
                message: launched ? "Mirror's command service is not ready. Check first-launch prompts, then run status again." : "The running Mirror process does not expose its command service. Save your work and reopen the selected app before trying status again." };
        }
        if (!result || typeof result.ok !== "boolean" || typeof result.status !== "string") failure("invalid_response", "Mirror returned an invalid command response.");
        result.requestID = request.requestID;
        return result;
    }

    function runNativeCommand(path, request) {
        var fm = $.NSFileManager.defaultManager;
        var folder = ObjC.unwrap($.NSTemporaryDirectory()) + "mirror-agent-" + ObjC.unwrap($.NSUUID.UUID.UUIDString);
        if (!fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(folder), false, $({ NSFilePosixPermissions: 448 }), null)) failure("transport_error", "Could not create a private command buffer.");
        var task = $.NSTask.alloc.init, outputHandle = null, inputPipe = $.NSPipe.pipe;
        try {
            var outputPath = folder + "/response.json";
            if (!fm.createFileAtPathContentsAttributes($(outputPath), $.NSData.data, $({ NSFilePosixPermissions: 384 }))) failure("transport_error", "Could not create a private response buffer.");
            outputHandle = $.NSFileHandle.fileHandleForWritingAtPath($(outputPath));
            task.executableURL = $.NSURL.fileURLWithPath($(path + "/Contents/MacOS/Mirror"));
            task.arguments = $(["--agent-command"]);
            task.standardInput = inputPipe;
            task.standardOutput = outputHandle;
            task.standardError = $.NSFileHandle.fileHandleWithNullDevice;
            try { task.launch; }
            catch (_) { failure("transport_error", "Could not start Mirror's local command client."); }
            inputPipe.fileHandleForWriting.writeData($(JSON.stringify(request) + "\n").dataUsingEncoding($.NSUTF8StringEncoding));
            inputPipe.fileHandleForWriting.closeFile;
            var deadline = Date.now() + 6500;
            while (task.running && Date.now() < deadline) $.NSThread.sleepForTimeInterval(0.025);
            if (task.running) {
                task.terminate;
                failure("timeout", "Mirror did not reply in time. The change may have completed; run status before deciding whether to retry, and retain the same request ID.");
            }
            outputHandle.closeFile; outputHandle = null;
            var attributes = fm.attributesOfItemAtPathError($(outputPath), null);
            if (!attributes || Number(ObjC.unwrap(attributes.objectForKey($("NSFileSize")))) > 65536) failure("invalid_response", "Mirror's command response exceeded the allowed size.");
            var data = $.NSData.dataWithContentsOfFile($(outputPath));
            var raw = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
            if (!raw || raw.isNil()) failure("invalid_response", "Mirror did not return a UTF-8 command response.");
            var result;
            try { result = JSON.parse(ObjC.unwrap(raw)); } catch (_) { failure("invalid_response", "Mirror did not return a valid command response."); }
            if (!result || typeof result.ok !== "boolean" || typeof result.status !== "string") failure("invalid_response", "Mirror returned an invalid command response.");
            return result;
        } finally {
            try { inputPipe.fileHandleForWriting.closeFile; } catch (_) {}
            try { if (outputHandle) outputHandle.closeFile; } catch (_) {}
            fm.removeItemAtPathError($(folder), null);
        }
    }

    function nativeRuntime() {
        var version = $.NSProcessInfo.processInfo.operatingSystemVersion;
        var systemVersion = version.majorVersion + "." + version.minorVersion + "." + version.patchVersion;
        function runningAppPaths() {
            var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($(bundleID));
            if (apps.count > 32) {
                failure("ambiguous_app", "Too many Mirror application instances are running. Choose the intended application with --app.");
            }
            var paths = [];
            for (var i = 0; i < apps.count; i++) {
                var url = apps.objectAtIndex(i).bundleURL;
                if (!url || url.isNil()) continue;
                var path = ObjC.unwrap(url.path.stringByStandardizingPath.stringByResolvingSymlinksInPath);
                if (typeof path === "string" && path[0] === "/" && paths.indexOf(path) < 0) paths.push(path);
            }
            return paths;
        }
        return {
            systemVersion: systemVersion,
            uuid: function () { return ObjC.unwrap($.NSUUID.UUID.UUIDString); },
            sleep: function (seconds) { $.NSThread.sleepForTimeInterval(seconds); },
            command: runNativeCommand,
            home: ObjC.unwrap($.NSHomeDirectory()),
            runningAppPaths: runningAppPaths,
            exists: function (path) { return Boolean($.NSFileManager.defaultManager.fileExistsAtPath($(path))); },
            inspect: function (path) { return inspectApp(path, systemVersion); },
            isRunning: function (path) {
                var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($(bundleID));
                for (var i = 0; i < apps.count; i++) {
                    var url = apps.objectAtIndex(i).bundleURL;
                    if (url && !url.isNil() && ObjC.unwrap(url.path.stringByResolvingSymlinksInPath) === path) return true;
                }
                return false;
            },
            open: function (args) {
                var task = $.NSTask.alloc.init;
                task.executableURL = $.NSURL.fileURLWithPath("/usr/bin/open");
                task.arguments = $(args);
                // Suppress native diagnostics that could contain private paths or IDs.
                task.standardOutput = $.NSFileHandle.fileHandleWithNullDevice;
                task.standardError = $.NSFileHandle.fileHandleWithNullDevice;
                try {
                    task.launch;
                    var deadline = Date.now() + 6500;
                    while (task.running && Date.now() < deadline) $.NSThread.sleepForTimeInterval(0.025);
                    if (task.running) { task.terminate; failure("launch_failed", "macOS did not finish the launch request. Check Mirror before trying status again."); }
                }
                catch (_) { failure("launch_failed", "macOS could not launch Mirror. Open the selected app manually to complete its first launch."); }
                if (task.terminationStatus !== 0) failure("launch_failed", "macOS rejected the launch request. Open the selected app manually to complete its first launch.");
            }
        };
    }

    function response(argv, runtime) {
        var options;
        try { options = parse(argv); return execute(options, runtime || nativeRuntime()); }
        catch (error) {
            return { ok: false, status: error.mirrorCode || "internal_error", requestID: options && options.requestID,
                message: error.mirrorCode ? error.message : "Mirror could not complete the request. No conversation contents were read." };
        }
    }

    return { parse: parse, commandRequest: commandRequest, arm64Executable: arm64Executable, versionAtLeast: versionAtLeast,
        validateMetadata: validateMetadata, findApp: findApp, execute: execute, response: response, inspectApp: inspectApp, runNativeCommand: runNativeCommand };
}());

function run(argv) {
    var result = MirrorHelper.response(argv);
    var data = $(JSON.stringify(result) + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
    $.exit(result.ok ? 0 : 1);
}
