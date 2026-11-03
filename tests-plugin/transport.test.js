ObjC.import("Foundation");
function run(argv) {
    var source = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($(argv[0]), $.NSUTF8StringEncoding, null));
    var helper = new Function(source + "\nreturn MirrorHelper;")();
    var response = helper.runNativeCommand(argv[1], {
        requestID: "20000000-0000-0000-0000-000000000001", action: "find", expectedRevision: 7,
        windowID: "10000000-0000-0000-0000-000000000001", query: "中文 🍵 & ` $(touch never) ' \" --query"
    });
    if (!response.ok || response.status !== "fixture_ok" || response.padding.length !== 30000 || response.echo.query !== "中文 🍵 & ` $(touch never) ' \" --query") throw Error("Native stdin/stdout boundaries failed");
    ["oversized", "invalid", "timeout"].forEach(function (action) {
        var caught = false;
        try { helper.runNativeCommand(argv[1], {requestID:"20000000-0000-0000-0000-000000000001",action:action}); }
        catch (error) { if (error.mirrorCode !== (action === "timeout" ? "timeout" : "invalid_response")) throw error; caught=true; }
        if (!caught) throw Error("Accepted " + action + " transport result");
    });
    var failure = helper.runNativeCommand(argv[1], {requestID:"20000000-0000-0000-0000-000000000001",action:"failure"});
    if (failure.ok !== false || failure.status !== "agent_paused") throw Error("Nonzero exit dropped structured native error");
    return "PASS: 5 native transport tests (Unicode, 30 KB response, size/JSON limits, timeout, nonzero JSON error; isolated fixture only).";
}
