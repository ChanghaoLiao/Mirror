ObjC.import("Foundation");
ObjC.import("stdlib");
function run(argv) {
    var source = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($(argv[0]), $.NSUTF8StringEncoding, null));
    var helper = new Function(source + "\nreturn MirrorHelper;")();
    var passed = 0, windowID = "10000000-0000-0000-0000-000000000001", requestID = "20000000-0000-0000-0000-000000000001";
    function assert(condition, message) { if (!condition) throw new Error(message); }
    function equal(actual, expected) { assert(JSON.stringify(actual) === JSON.stringify(expected), "Unexpected value: " + JSON.stringify(actual)); }
    function test(name, fn) { try { fn(); passed++; } catch (error) { throw new Error(name + ": " + error.message); } }
    function runtime() {
        return {
            home: "/Users/test user", systemVersion: "14.0.0", opened: [], inspected: [], checked: [], commands: [], sleeps: [],
            uuid: function () { return requestID; },
            runningAppPaths: function () { return []; },
            exists: function (path) { this.checked.push(path); return path === "/Applications/Mirror.app"; },
            inspect: function (path) { this.inspected.push(path); return { path: path, version: "1.0.0" }; },
            isRunning: function () { return true; },
            open: function (args) { this.opened.push(args); },
            sleep: function (seconds) { this.sleeps.push(seconds); },
            command: function (path, request) { this.commands.push({ path: path, request: request }); return { ok: true, status: "ready", revision: 7, windows: [], agentEnabled: true }; }
        };
    }
    function rejects(args, status) {
        var rt = runtime(), result = helper.response(args, rt);
        equal(result.ok, false); equal(result.status, status || "invalid_arguments");
        equal(rt.commands, []); equal(rt.opened, []); return result;
    }
    function expectedError(fn, code) {
        try { fn(); } catch (error) { equal(error.mirrorCode, code); return; } throw new Error("Expected " + code);
    }
    function metadata() { return { CFBundleIdentifier: "local.mirror.companion", CFBundleExecutable: "Mirror", CFBundlePackageType: "APPL", CFBundleShortVersionString: "1.0.0", LSMinimumSystemVersion: "14.0" }; }
    function mutation(command, extra) { return [command, "--revision", "7", "--window", windowID].concat(extra || []); }

    test("help requires no runtime or launch", function () { var rt=runtime(); equal(helper.response(["--help"],rt).status,"help"); equal(rt.inspected,[]); equal(rt.commands,[]); });
    test("status returns real native state", function () { var rt=runtime(), result=helper.response(["status"],rt); equal(result.revision,7); equal(result.windows,[]); equal(rt.commands[0].request,{requestID:requestID,action:"status"}); equal(rt.opened,[]); });
    test("list is a read-only snapshot without revision", function () { var rt=runtime(); helper.response(["list"],rt); equal(rt.commands[0].request.action,"list"); equal(rt.commands[0].request.expectedRevision,undefined); });
    test("setup required is retained without permission claims", function () { var rt=runtime(); rt.command=function(){return{ok:false,status:"setup_required",revision:0,windows:[]}}; equal(helper.response(["status"],rt).status,"setup_required"); equal(rt.opened,[]); });
    test("status launches exact app without a reference", function () { var rt=runtime(); rt.isRunning=function(){return false}; var r=helper.response(["status"],rt); equal(rt.opened,[["-g","-a","/Applications/Mirror.app","--args","--agent-launch"]]); equal(r.revision,7); });
    test("follow-up status does not restart a human-quit app",function(){var rt=runtime();rt.isRunning=function(){return false};equal(helper.response(["status","--launch","false"],rt).status,"app_not_running");equal(rt.opened,[]);equal(rt.commands,[]);});
    test("no-launch status still reads a running app",function(){var rt=runtime();equal(helper.response(["status","--launch","false"],rt).revision,7);equal(rt.commands[0].request.launch,undefined);equal(rt.opened,[]);});
    test("launch selector is read-only only",function(){rejects(mutation("close",["--launch","true"]));rejects(["status","--launch","yes"]);});
    test("startup retries only read-only service absence", function () { var rt=runtime(), n=0; rt.isRunning=function(){return false}; rt.command=function(path,request){this.commands.push(request); n++; return n<3?{ok:false,status:"service_unavailable"}:{ok:true,status:"ready",revision:0,windows:[]};}; equal(helper.response(["status"],rt).status,"ready"); equal(rt.commands.length,3); equal(rt.sleeps,[0.2,0.2]); equal(rt.commands[0].requestID,rt.commands[2].requestID); });
    test("startup has a bounded retry count", function () { var rt=runtime(); rt.isRunning=function(){return false}; rt.command=function(){this.commands.push(1);return{ok:false,status:"service_unavailable"}}; equal(helper.response(["status"],rt).status,"startup_pending"); equal(rt.commands.length,11); });
    test("running process with unavailable service requires restart", function () { var rt=runtime();rt.command=function(){this.commands.push(1);return{ok:false,status:"service_unavailable"}}; equal(helper.response(["status"],rt).status,"restart_required"); equal(rt.commands.length,1); equal(rt.opened,[]); });
    test("mutation does not launch missing process", function () { var rt=runtime();rt.isRunning=function(){return false};equal(helper.response(mutation("close"),rt).status,"app_not_running");equal(rt.opened,[]);equal(rt.commands,[]); });
    test("old app is rejected before launch", function () { var rt=runtime();rt.inspect=function(path){return{path:path,version:"0.2.1"}};rt.isRunning=function(){return false};equal(helper.response(["status"],rt).status,"upgrade_required");equal(rt.commands,[]);equal(rt.opened,[]); });
    test("old app mutation is rejected before transport", function () { var rt=runtime();rt.inspect=function(path){return{path:path,version:"0.2.1"}};equal(helper.response(mutation("close"),rt).status,"upgrade_required");equal(rt.commands,[]); });
    test("open defaults to reusable conversation", function () { var rt=runtime();helper.response(["open","--conversation","known","--revision","7"],rt);equal(rt.commands[0].request,{requestID:requestID,action:"open",expectedRevision:7,conversationID:"known"});equal(rt.commands.length,1); });
    test("explicit new reference survives encoding", function () {var rt=runtime();helper.response(["open","--conversation","known","--revision","7","--new","true"],rt);equal(rt.commands[0].request.newWindow,true);});
    test("open can retarget explicitly chosen window", function () {var rt=runtime();helper.response(mutation("open",["--conversation","known","--message","turn/item"]),rt);equal(rt.commands[0].request.windowID,windowID);equal(rt.commands[0].request.messageID,"turn/item");});
    test("Unicode and punctuation queries are JSON data", function () {var rt=runtime(), query="对话 🍵 &message=假的%20 \" ' ` $(touch never)";helper.response(mutation("find",["--query",query]),rt);equal(rt.commands[0].request.query,query);equal(rt.opened,[]);});
    test("native identifier alphabet is preserved", function () {var rt=runtime();helper.response(["open","--conversation","thread_123-abc.def","--message","turn_1-abc/item_2.def","--revision","7"],rt);equal(rt.commands[0].request.conversationID,"thread_123-abc.def");equal(rt.commands[0].request.messageID,"turn_1-abc/item_2.def");});
    ["中文","a/b","a..b","$(touch nope)","a b",new Array(258).join("a")].forEach(function(id,index){test("native conversation restriction "+index,function(){rejects(["open","--conversation",id,"--revision","7"]);});});
    ["turn/中文","turn/..","turn/a b","turn/item/extra","/item","turn/",new Array(258).join("a")+"/"+new Array(258).join("b")].forEach(function(id,index){test("native message restriction "+index,function(){rejects(["open","--conversation","known","--message",id,"--revision","7"]);});});
    test("query limit counts UTF-8 bytes",function(){var rt=runtime(),query=new Array(1025).join("🍵");equal(helper.response(mutation("find",["--query",query]),rt).ok,true);rejects(mutation("find",["--query",query+"a"]));rejects(mutation("find",["--query",new Array(1367).join("中")]));});
    test("query uses native Unicode control classification",function(){rejects(mutation("find",["--query","a\u200bb"]));});
    test("frame native minimum accepted",function(){var rt=runtime();equal(helper.response(mutation("frame",["--frame",'{"x":-100000,"y":100000,"width":280,"height":260}']),rt).ok,true);});
    [[279,260],[280,259],[100001,260]].forEach(function(size,index){test("native frame restriction "+index,function(){rejects(mutation("frame",["--frame",JSON.stringify({x:0,y:0,width:size[0],height:size[1]})]));});});
    test("font accepts native range endpoints", function () { ["11","26","15.5"].forEach(function(v){var rt=runtime();equal(helper.response(mutation("font",["--font-size",v]),rt).ok,true);equal(rt.commands[0].request.fontSize,Number(v));}); });
    test("find can clear text", function () {var rt=runtime();helper.response(mutation("find",["--query",""]),rt);equal(rt.commands[0].request.query,"");});
    test("query beginning with dashes remains data", function () {var rt=runtime();helper.response(mutation("find",["--query","--example"]),rt);equal(rt.commands[0].request.query,"--example");});
    test("frame transmits finite geometry", function () {var rt=runtime(),frame={x:-100,y:24,width:450,height:700};helper.response(mutation("frame",["--frame",JSON.stringify(frame)]),rt);equal(rt.commands[0].request.frame,frame);});
    ["duplicate","close","hide","show","refresh","cancel","copy","bind","unbind"].forEach(function(command){test(command+" sends one scoped request",function(){var rt=runtime();helper.response(mutation(command),rt);equal(rt.commands.length,1);equal(rt.commands[0].request.action,command);equal(rt.commands[0].request.windowID,windowID);equal(rt.commands[0].request.expectedRevision,7);});});
    ["revision_conflict","agent_paused","ambiguous_window","permission_required","host_not_found","timeout"].forEach(function(status){test(status+" is never automatically retried",function(){var rt=runtime();rt.command=function(path,request){this.commands.push(request);return{ok:false,status:status,revision:8,windows:[]};};var result=helper.response(mutation("bind"),rt);equal(result.status,status);equal(result.revision,8);equal(rt.commands.length,1);equal(rt.opened,[]);equal(rt.sleeps,[]);});});
    test("caller request ID remains stable",function(){var rt=runtime(),id="30000000-0000-0000-0000-000000000003";var result=helper.response(mutation("close",["--request-id",id]),rt);equal(rt.commands[0].request.requestID,id);equal(result.requestID,id);});
    test("transport exception retains request ID without diagnostic leaks",function(){var rt=runtime();rt.command=function(){throw new Error("private body /Users/private")};var result=helper.response(mutation("close"),rt);equal(result.status,"internal_error");equal(result.requestID,requestID);assert(!/private body|Users/.test(JSON.stringify(result)),"Leaked diagnostics");});
    test("explicit path skips discovery",function(){var rt=runtime(),path="/Chosen folder/Mirror.app";rt.runningAppPaths=function(){throw Error("must not enumerate")};helper.response(["status","--app",path],rt);equal(rt.checked,[]);equal(rt.inspected,[path]);equal(rt.commands[0].path,path);});
    test("unique running path wins",function(){var rt=runtime(),path="/Build/Mirror.app";rt.runningAppPaths=function(){return[path,path]};helper.response(["status"],rt);equal(rt.checked,[]);equal(rt.inspected,[path]);});
    test("distinct running copies stay ambiguous",function(){var rt=runtime();rt.runningAppPaths=function(){return["/Build/Mirror.app","/Applications/Mirror.app"]};equal(helper.response(["status"],rt).status,"ambiguous_app");equal(rt.inspected,[]);equal(rt.commands,[]);});
    test("multiple installations stay ambiguous",function(){var rt=runtime();rt.exists=function(){return true};equal(helper.response(["status"],rt).status,"ambiguous_app");equal(rt.commands,[]);});
    test("discovery checks only documented locations",function(){var rt=runtime();rt.exists=function(path){this.checked.push(path);return false};equal(helper.response(["status"],rt).status,"app_not_found");equal(rt.checked,["/Applications/Mirror.app","/Users/test user/Applications/Mirror.app"]);});
    test("equivalent resolved installs are unambiguous",function(){var rt=runtime();rt.exists=function(){return true};rt.inspect=function(){return{path:"/Resolved/Mirror.app",version:"1.0.0"}};equal(helper.response(["status"],rt).ok,true);equal(rt.commands[0].path,"/Resolved/Mirror.app");});
    test("app path punctuation stays a single data argument",function(){var rt=runtime(),path="/Mirror $(touch nope) ' \" &.app";rt.isRunning=function(){return false};helper.response(["status","--app",path],rt);equal(rt.opened[0][2],path);equal(rt.commands[0].path,path);});
    [[],["status","--revision","1"],["list","--window",windowID],["open"],["open","--conversation","a"],["open","--revision","7"],["close","--revision","7"],["close","--window",windowID],
     ["close","--window","not-uuid","--revision","7"],["close","--window",windowID,"--revision","-1"],["close","--window",windowID,"--revision","9007199254740992"],
     ["status","--request-id","bad"],["open","--conversation","a","--revision","7","--message","item"],["open","--conversation","a","--revision","7","--message","turn/item/extra"],
     ["open","--conversation","a","--revision","7","--new","yes"],["open","--conversation","a","--revision","7","--new","true","--window",windowID],
     ["open","--conversation","","--revision","7"],["open","--conversation","\ud800","--revision","7"],["open","--conversation","a\nb","--revision","7"],
     ["status","--app","Mirror.app"],["status","--app","/bin/sh"],["status","--app","/A.app\n"],["__proto__"],["constructor"],["status","__proto__","x"],["status","--unknown","x"],["status","--app"],["status","--app","/A.app","--app","/B.app"]
    ].slice(1).forEach(function(args,index){test("invalid options "+index,function(){rejects(args);});});
    [["font",["--font-size","10"]],["font",["--font-size","27"]],["font",["--font-size","NaN"]],["font",["--font-size","Infinity"]],["font",[]],
     ["find",[]],["find",["--query","a\nb"]],["find",["--query","\ud800"]],["frame",["--frame","{}"]],["frame",["--frame","[]"]],["frame",["--frame","{bad}"]],
     ["frame",["--frame",'{"x":0,"y":0,"width":0,"height":600}']],["frame",["--frame",'{"x":"0","y":0,"width":400,"height":600}']],["frame",["--frame",'{"x":0,"y":0,"width":400,"height":600,"extra":true}']]
    ].forEach(function(spec,index){test("invalid action data "+index,function(){rejects(mutation(spec[0],spec[1]));});});
    test("wrong bundle identity", function () { var info = metadata(); info.CFBundleIdentifier = "com.apple.calculator"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("executable cannot escape bundle", function () { var info = metadata(); info.CFBundleExecutable = "../../bin/sh"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("invalid package type", function () { var info = metadata(); info.CFBundlePackageType = "BNDL"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("minimum supported app version accepted", function () { helper.validateMetadata(metadata(), "14.0"); });
    test("newer app version accepted", function () { var info = metadata(); info.CFBundleShortVersionString = "1.10.0"; helper.validateMetadata(info, "14.0"); });
    test("old app version rejected", function () { var info = metadata(); info.CFBundleShortVersionString = "0.2.0"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "unsupported_app_version"); });
    test("missing app version rejected", function () { var info = metadata(); delete info.CFBundleShortVersionString; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("nonnumeric app version rejected", function () { var info = metadata(); info.CFBundleShortVersionString = "0.2.1-preview"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("two-part app version rejected", function () { var info = metadata(); info.CFBundleShortVersionString = "0.2"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("numeric metadata type rejected", function () { var info = metadata(); info.CFBundleShortVersionString = 1; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("old app status cannot advertise ready capabilities", function () {
        var rt = runtime();
        rt.inspect = function () {
            var info = metadata(); info.CFBundleShortVersionString = "0.1.99";
            helper.validateMetadata(info, this.systemVersion);
            return { path: "/Applications/Mirror.app", version: info.CFBundleShortVersionString };
        };
        var result = helper.response(["status", "--app", "/Applications/Mirror.app"], rt);
        equal(result.ok, false); equal(result.status, "unsupported_app_version");
        equal(result.capabilities, undefined); equal(rt.opened, []);
    });
    test("missing minimum OS", function () { var info = metadata(); delete info.LSMinimumSystemVersion; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "invalid_app"); });
    test("app requires newer OS", function () { var info = metadata(); info.LSMinimumSystemVersion = "15.0"; expectedError(function () { helper.validateMetadata(info, "14.0"); }, "unsupported_app_version"); });
    test("numeric version comparison", function () { equal(helper.versionAtLeast("14.10", "14.9"), true); equal(helper.versionAtLeast("14.0", "14.0.1"), false); });
    test("arm64 Mach-O executable header", function () { equal(helper.arm64Executable([0xcf, 0xfa, 0xed, 0xfe, 12, 0, 0, 1, 0, 0, 0, 0, 2, 0, 0, 0]), true); });
    test("x86 Mach-O rejected", function () { equal(helper.arm64Executable([0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1, 0, 0, 0, 0, 2, 0, 0, 0]), false); });
    test("arm64 library rejected", function () { equal(helper.arm64Executable([0xcf, 0xfa, 0xed, 0xfe, 12, 0, 0, 1, 0, 0, 0, 0, 6, 0, 0, 0]), false); });
    test("shell script rejected", function () { equal(helper.arm64Executable([35, 33, 47, 98, 105, 110, 47, 115, 104]), false); });
    test("truncated executable rejected", function () { equal(helper.arm64Executable([0xcf, 0xfa, 0xed, 0xfe]), false); });
    test("universal header with arm64 slice", function () { equal(helper.arm64Executable([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 1, 1, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0x10, 0, 0, 0, 0x20, 0, 0, 0, 0, 0]), true); });
    test("truncated universal header rejected", function () { equal(helper.arm64Executable([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 1, 1, 0, 0, 12]), false); });
    test("native inspection rejects missing app",function(){expectedError(function(){helper.inspectApp("/MirrorHelperTest-does-not-exist.app","14.0")},"invalid_app")});
    test("native inspection rejects a different app",function(){expectedError(function(){helper.inspectApp("/System/Applications/Calculator.app","99.0")},"invalid_app")});
    return "PASS: " + passed + " helper tests (no app launches, no conversation reads).";
}
