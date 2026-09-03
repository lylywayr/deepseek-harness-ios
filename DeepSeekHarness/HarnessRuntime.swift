import Foundation
import WebKit

struct HarnessSessionSummary {
    let id: String
    var title: String
    var cwd: String
    var updatedAt: Double
    var running: Bool
    var blank: Bool
    var preset: String
    var permission: String
    var provider: String
    var model: String
    var turns: Int
    var steps: Int
    var contextUsed: Double?
}

struct HarnessWorkspace {
    let id: String
    let title: String
    let path: String
    let sessionIDs: [String]
}

struct HarnessModelOption {
    let provider: String
    let providerName: String
    let model: String
    let modelName: String
    let reasoning: [[String: String]]
    var key: String { "\(provider)/\(model)" }
}

struct HarnessConversationItem {
    enum Kind: String { case user, assistant, tool, system }
    let id: String
    let kind: Kind
    var text: String
    var subtitle: String?
    let seq: Int
    let time: Double
}

@MainActor
final class HarnessRuntime: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let baseURL: URL
    private(set) var webView: WKWebView!
    private(set) var sessions: [HarnessSessionSummary] = []
    private(set) var workspaces: [HarnessWorkspace] = []
    private(set) var models: [HarnessModelOption] = []
    private(set) var items: [HarnessConversationItem] = []
    private(set) var selectedSessionID: String?
    private(set) var isLoading = true
    private(set) var isGenerating = false
    private(set) var hasMore = false
    private(set) var connected = false
    private(set) var lastError: String?
    private(set) var statusText = "正在连接"
    var onChange: (() -> Void)?
    var onNavigationChange: (() -> Void)?
    var onApproval: (([String: Any]) -> Void)?

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
        let controller = WKUserContentController()
        controller.add(self, name: "harnessRuntime")
        controller.addUserScript(WKUserScript(source: Self.runtimeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isHidden = true
        webView.alpha = 0.01
        webView.accessibilityElementsHidden = true
    }

    deinit { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "harnessRuntime") }

    func mount(in host: UIView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }

    func start() { webView.load(URLRequest(url: baseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)) }
    func refresh() { call("refresh") }
    func openSession(_ id: String) { call("openSession", arguments: [id]) }
    func createSession(workspaceID: String?) { call("createSession", arguments: [workspaceID as Any]) }
    func send(_ text: String, mode: String = "queue", images: [[String: Any]] = []) { call("prompt", arguments: [text, mode, images]) }
    func cancel() { call("cancel") }
    func loadOlder() { call("loadOlder") }
    func selectModel(_ option: HarnessModelOption, reasoning: String? = nil) {
        call("selectModel", arguments: [option.provider, option.model, reasoning as Any])
    }
    func setPermission(_ value: String) { call("setPermission", arguments: [value]) }
    func rename(_ title: String) { call("rename", arguments: [title]) }
    func answerApproval(clientID: String, eventID: String, decision: String) {
        call("answerApproval", arguments: [clientID, eventID, decision])
    }

    private func call(_ method: String, arguments: [Any] = []) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__harnessNative?.\(method).apply(window.__harnessNative, \(json))") { [weak self] _, error in
            if let error { Task { @MainActor in self?.acceptError(error.localizedDescription) } }
        }
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor in self.accept(body) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        call("refresh")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        acceptError(error.localizedDescription)
    }

    private func accept(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "state": parseState(body)
        case "error": acceptError(body["message"] as? String ?? "Harness 请求失败")
        case "approval": onApproval?(body)
        default: break
        }
    }

    private func acceptError(_ text: String) {
        lastError = text
        statusText = "连接异常"
        isLoading = false
        onChange?()
        onNavigationChange?()
    }

    private func parseState(_ body: [String: Any]) {
        connected = body["connected"] as? Bool ?? connected
        isLoading = body["loading"] as? Bool ?? false
        isGenerating = body["generating"] as? Bool ?? false
        hasMore = body["hasMore"] as? Bool ?? false
        selectedSessionID = body["selectedSessionId"] as? String
        statusText = connected ? (isGenerating ? "正在运行" : "已连接") : "正在连接"
        lastError = body["error"] as? String
        sessions = (body["sessions"] as? [[String: Any]] ?? []).compactMap(Self.session)
        workspaces = (body["workspaces"] as? [[String: Any]] ?? []).compactMap(Self.workspace)
        models = (body["models"] as? [[String: Any]] ?? []).compactMap(Self.model)
        items = (body["items"] as? [[String: Any]] ?? []).compactMap(Self.item)
        onChange?()
        onNavigationChange?()
    }

    private static func session(_ value: [String: Any]) -> HarnessSessionSummary? {
        guard let id = value["id"] as? String else { return nil }
        return HarnessSessionSummary(id: id, title: value["title"] as? String ?? "新会话", cwd: value["cwd"] as? String ?? "", updatedAt: (value["updatedAt"] as? NSNumber)?.doubleValue ?? 0, running: value["running"] as? Bool ?? false, blank: value["blank"] as? Bool ?? false, preset: value["preset"] as? String ?? "standard", permission: value["permission"] as? String ?? "", provider: value["provider"] as? String ?? "", model: value["model"] as? String ?? "", turns: (value["turns"] as? NSNumber)?.intValue ?? 0, steps: (value["steps"] as? NSNumber)?.intValue ?? 0, contextUsed: (value["contextUsed"] as? NSNumber)?.doubleValue)
    }

    private static func workspace(_ value: [String: Any]) -> HarnessWorkspace? {
        guard let id = value["id"] as? String else { return nil }
        return HarnessWorkspace(id: id, title: value["title"] as? String ?? "工作区", path: value["path"] as? String ?? "", sessionIDs: value["sessionIds"] as? [String] ?? [])
    }

    private static func model(_ value: [String: Any]) -> HarnessModelOption? {
        guard let provider = value["provider"] as? String, let model = value["model"] as? String else { return nil }
        return HarnessModelOption(provider: provider, providerName: value["providerName"] as? String ?? provider, model: model, modelName: value["modelName"] as? String ?? model, reasoning: value["reasoning"] as? [[String: String]] ?? [])
    }

    private static func item(_ value: [String: Any]) -> HarnessConversationItem? {
        guard let id = value["id"] as? String, let raw = value["kind"] as? String,
              let kind = HarnessConversationItem.Kind(rawValue: raw) else { return nil }
        return HarnessConversationItem(id: id, kind: kind, text: value["text"] as? String ?? "", subtitle: value["subtitle"] as? String, seq: (value["seq"] as? NSNumber)?.intValue ?? -1, time: (value["time"] as? NSNumber)?.doubleValue ?? 0)
    }

    private static let runtimeScript = #"""
    (() => {
      if (window.__harnessNative) return;
      const state = {connected:false,loading:true,generating:false,hasMore:false,error:null,sessions:[],workspaces:[],models:[],items:[],selectedSessionId:null,cursor:null,oldestSeq:null};
      let socket, stopped = false, reconnectTimer, liveText = new Map(), seen = new Set();
      const post = x => window.webkit.messageHandlers.harnessRuntime.postMessage(x);
      const publish = () => post({type:'state', ...state});
      const fail = e => { state.error = e?.message || String(e); state.loading=false; post({type:'error',message:state.error}); publish(); };
      const rpc = async (endpoint,args={}) => {
        const rpcId = crypto.randomUUID();
        const response = await fetch('/api/'+endpoint,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({type:'client-request',rpcId,method:endpoint,payload:{args}})});
        if(!response.ok) throw new Error(`HTTP ${response.status}: ${endpoint}`);
        const envelope=await response.json(); if(envelope.rpcId!==rpcId) throw new Error('RPC correlation mismatch');
        if(!envelope.result?.ok) throw new Error(envelope.result?.error?.message || `${endpoint} failed`);
        return envelope.result.value;
      };
      const projection = s => s?.projections?.values || {};
      const route = p => p?.modelSelection?.next || p?.modelSelection?.lastUsed || {};
      const sessionOf = s => { const p=projection(s), r=route(p), cp=p.contextPressure||{}; return {id:s.sessionId,title:p.title||'新会话',cwd:s.cwd||'',updatedAt:s.updatedAt||0,running:!!s.running,blank:!!s.blank,preset:p.agentPreset||'standard',permission:p.permissions?.currentValue||'',provider:r.provider||'',model:r.model||'',turns:p.sessionStats?.turns||0,steps:p.sessionStats?.steps||0,contextUsed:cp.contextWindow?((cp.pressureTokens||0)/cp.contextWindow):null}; };
      const refresh = async () => { try { state.loading=true; publish(); const [sl,mc]=await Promise.all([rpc('session/list',{_request:{}}),rpc('session/modelCatalog',{})]); state.sessions=(sl.items||[]).map(sessionOf); state.models=[]; for(const g of mc.groups||[]) for(const m of g.models||[]) state.models.push({provider:g.id,providerName:g.name,model:m.id,modelName:m.name,reasoning:m.reasoning?.efforts||[]}); if(!state.selectedSessionId && state.sessions.length) state.selectedSessionId=state.sessions.find(s=>!s.blank)?.id||state.sessions[0].id; state.connected=true;state.loading=false;state.error=null; publish(); openGlobalStreams(); if(state.selectedSessionId) openFollow(state.selectedSessionId); } catch(e){fail(e)} };
      const textBlocks = content => { if(!Array.isArray(content)) return ''; return content.map(b=>{ if(b?.type==='text')return b.text||''; if(b?.type==='tool-result')return textBlocks(b.content); if(b?.type==='image')return `[图片] ${b.name||''}`; return ''; }).filter(Boolean).join('\n'); };
      const add = (item,prepend=false) => { if(!item.text?.trim() || seen.has(item.id))return; seen.add(item.id); if(prepend)state.items.unshift(item); else state.items.push(item); };
      const parseEvent = (row,prepend=false) => { let e=row?.event||row; if(!e)return; const type=e.type||'', data=e.data||{}, seq=e.seq??row.seq??-1, id=`${seq}:${type}`; if(seq>=0)state.oldestSeq=state.oldestSeq==null?seq:Math.min(state.oldestSeq,seq);
        if(type==='user/message') add({id,kind:'user',text:textBlocks(data.content),seq,time:e.time||0},prepend);
        else if(type==='assistant/message') { add({id,kind:'assistant',text:textBlocks(data.message?.content),seq,time:e.time||0},prepend); state.generating=false; }
        else if(type==='tool/call') add({id,kind:'tool',text:data.name||'工具调用',subtitle:data.arguments||'',seq,time:e.time||0},prepend);
        else if(type==='tool/result') add({id,kind:'tool',text:textBlocks(data.message?.content)||'工具执行完成',subtitle:'结果',seq,time:e.time||0},prepend);
        else if(type==='command/run') add({id,kind:'system',text:`/${data.name||'command'}${data.args||''}`,subtitle:'指令',seq,time:e.time||0},prepend);
        else if(type==='command/done' && data.result?.text) add({id,kind:'system',text:data.result.text,subtitle:data.result.kind||'指令结果',seq,time:e.time||0},prepend);
        else if(type==='assistant/chunk') { const c=data.chunk||{}; if(c.type==='block-end'&&c.block?.type==='text'){ const key=`live:${data.turn}:${data.step}:${c.index}`; const at=state.items.findIndex(x=>x.id===key); const item={id:key,kind:'assistant',text:c.block.text||'',subtitle:'生成中',seq,time:e.time||0}; if(at>=0)state.items[at]=item; else state.items.push(item); state.generating=true; } if(c.type==='finish')state.generating=false; }
        else if(type.includes('error')) add({id,kind:'system',text:data.message||data.error||type,subtitle:'错误',seq,time:e.time||0},prepend);
      };
      const parseRecords = (records,prepend=false) => { const ordered=prepend?[...(records||[])].reverse():records||[]; for(const r of ordered)parseEvent(r,prepend); state.items.sort((a,b)=>a.seq-b.seq); };
      const openSocket = () => { if(socket && socket.readyState<2)return socket; const protocol=location.protocol==='https:'?'wss:':'ws:'; socket=new WebSocket(`${protocol}//${location.host}/api/remote.mux`); socket.onopen=()=>{state.connected=true;publish()}; socket.onmessage=ev=>{try{const f=JSON.parse(ev.data);if(f.type==='item')acceptStream(f.streamId,f.value);else if(f.type==='error')throw new Error(f.error?.message||'stream error')}catch(e){fail(e)}}; socket.onclose=()=>{socket=null;state.connected=false;publish();if(!stopped){clearTimeout(reconnectTimer);reconnectTimer=setTimeout(openGlobalStreams,2000)}}; return socket; };
      const openStream = (streamId,endpoint,args) => { const ws=openSocket(), message=()=>ws.send(JSON.stringify({type:'open',streamId,endpoint,payload:{args}})); if(ws.readyState===1)message(); else ws.addEventListener('open',message,{once:true}); };
      const openGlobalStreams=()=>{openStream('workspace','workspace/follow',{});openStream('control','session/control',{});openStream('events','$events',{})};
      const openFollow=id=>{ if(!id)return; state.items=[];seen.clear();state.cursor=null;state.oldestSeq=null;publish();openStream('follow','session/follow',{request:{address:{kind:'session',sessionId:id},maxMessages:50}}); };
      const mergeProjection=(id,key,value)=>{const s=state.sessions.find(x=>x.id===id);if(!s)return;if(key==='title')s.title=value||'新会话';else if(key==='permissions')s.permission=value?.currentValue||'';else if(key==='agentPreset')s.preset=value||'standard';else if(key==='modelSelection'){const r=value?.next||value?.lastUsed||{};s.provider=r.provider||'';s.model=r.model||''}else if(key==='sessionStats'){s.turns=value?.turns||0;s.steps=value?.steps||0}else if(key==='contextPressure')s.contextUsed=value?.contextWindow?(value.pressureTokens||0)/value.contextWindow:null;};
      const acceptStream=(id,v)=>{if(id==='workspace'){const b=v?.value;if(v?.type==='baseline')state.workspaces=(b?.items||[]).map(w=>({id:w.workspaceId,title:w.title,path:w.path,sessionIds:w.sessionIds||[]}));}
        else if(id==='control'){if(v?.type==='baseline'){const p=v.value?.projections||{};for(const [sid,b] of Object.entries(p))for(const [k,val] of Object.entries(b.values||{}))mergeProjection(sid,k,val);const q=v.value?.queues?.[state.selectedSessionId]||[],j=v.value?.jobs?.[state.selectedSessionId]||[];state.generating=q.length>0||j.some(x=>x.status==='running');}else if(v?.type==='projection')mergeProjection(v.sessionId,v.key,v.value);else if(v?.sessionId===state.selectedSessionId&&(v.type==='queue'||v.type==='jobs'))state.generating=(v.items||v.jobs||[]).some(x=>x.status?x.status==='running':true);}
        else if(id==='follow'){if(v?.type==='snapshot'){state.cursor=v.cursor;state.hasMore=!!v.hasMore;parseRecords(v.records||[]);}else parseEvent(v);}
        else if(id==='events'){if(v?.type==='waterfall')post({type:'approval',clientId:window.__harnessClientId,eventId:v.eventId,event:v.event,agentId:v.agentId,request:v.request});else if(v?.type==='ready')window.__harnessClientId=v.clientId;}
        publish(); };
      const openSession=async id=>{state.selectedSessionId=id;publish();openFollow(id)};
      const createSession=async workspaceId=>{try{const request={};if(workspaceId)request.workspaceId=workspaceId;const v=await rpc('session/create',{request});await refresh();openSession(v.sessionId)}catch(e){fail(e)}};
      const prompt=async(text,mode='queue',images=[])=>{if(!state.selectedSessionId||(!text.trim()&&!images.length))return;const rid=crypto.randomUUID();add({id:`pending:${rid}`,kind:'user',text:text||images.map(x=>`[图片] ${x.name||''}`).join('\n'),subtitle:'发送中',seq:Number.MAX_SAFE_INTEGER-1,time:Date.now()});state.generating=true;publish();try{await rpc('session/prompt',{request:{requestId:rid,sessionId:state.selectedSessionId,mode,content:[...(text.trim()?[{type:'text',text}]:[]),...images],clientTimeZone:Intl.DateTimeFormat().resolvedOptions().timeZone}})}catch(e){fail(e)}};
      const cancel=async()=>{try{await rpc('session/cancel',{request:{sessionId:state.selectedSessionId}});state.generating=false;publish()}catch(e){fail(e)}};
      const selectModel=async(provider,model,reasoning)=>{try{const request={sessionId:state.selectedSessionId,provider,model};if(reasoning)request.reasoningEffort=reasoning;await rpc('session/selectModel',{request});await refresh()}catch(e){fail(e)}};
      const setPermission=async value=>{try{await rpc('commands/execute',{agentId:state.selectedSessionId,line:`/permission ${value}`,images:[]})}catch(e){fail(e)}};
      const rename=async title=>{try{await rpc('session/rename',{request:{sessionId:state.selectedSessionId,title}});await refresh()}catch(e){fail(e)}};
      const loadOlder=async()=>{if(!state.selectedSessionId||state.cursor==null||state.oldestSeq==null)return;try{const v=await rpc('session/page',{request:{address:{kind:'session',sessionId:state.selectedSessionId},throughSeq:state.cursor,beforeSeq:state.oldestSeq,maxMessages:30}});parseRecords(v.records||[],true);state.hasMore=!!v.hasMore;publish()}catch(e){fail(e)}};
      const answerApproval=async(clientId,eventId,decision)=>{try{await rpc('$events/result',{clientId,eventId,outcome:{kind:'result',value:decision}})}catch(e){fail(e)}};
      window.__harnessNative={refresh,openSession,createSession,prompt,cancel,selectModel,setPermission,rename,loadOlder,answerApproval};
      addEventListener('DOMContentLoaded',()=>setTimeout(refresh,0),{once:true});
    })();
    """#
}
