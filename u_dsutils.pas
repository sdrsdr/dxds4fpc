unit u_dsutils;

interface
uses DirectShow,ActiveX,windows,classes;

function FPS2RT (fps:Double):REFERENCE_TIME;
function FPS2NS (fps:Double):Cardinal;  //for Sleep

Function CreateGraphBuilder (out gb_gb:IGraphBuilder):boolean;
Function AddFilterToGraph (gb_gb:IGraphBuilder; guid: TGUID; fltname:String; out filter:IBaseFilter):boolean;

Function FindPin (filter:IBaseFilter; pinname:String; out pin:IPin):boolean;

Type TPinEnum=function (const pin:IPin):Boolean of object;
Function EnumPinsCB (filter:IBaseFilter; callback:TPinEnum):boolean; //if callback (pin) then break;

Procedure EnumPins (filter:IBaseFilter);

function ConnectPins (gb_gb:IGraphBuilder; flt_from:IBaseFilter; pin_from:String; flt_to:IBaseFilter; pin_to:string):boolean;


Type TGraphEnum=function (f:IBaseFilter;guid:PGUID):Boolean of object;
function EnumGraphCB (gb_gb:IGraphBuilder;cb:TGraphEnum):boolean;

function FreeGraph (gb_gb:IGraphBuilder; keepguids:String):boolean;
function DisconnectPin (gb_gb:IGraphBuilder;  flt:IBaseFilter; pin:String):boolean;

function StartGraph (gb_gb:IGraphBuilder; var isRuning:boolean):boolean;
function StopGraph (gb_gb:IGraphBuilder; var isRuning:boolean):Boolean;

Function LoadFltState (filename:String;flt:IBaseFilter;stmnm:string='flt'):boolean;
Function StoreFltState (filename:String;flt:IBaseFilter;stmnm:string='flt'):boolean;

function publish_graph (gb:IGraphBuilder):HResult;

function ShowPropPage (flt:IBaseFilter; ppn:String='PROPS';wnd:HWND=0):boolean;



type
	TBaseFilterHolder=class
		bfr:IBaseFilter;
		constructor Create (bf:IBaseFilter);
		destructor Destroy ();override;
	end;


Procedure EnumDevices (cat:TGUID; listto:TStrings);
Function FindDeviceByName (cat:TGUID; name:String):IBaseFilter;


const olepro32 = 'olepro32.dll';
  
  
  function OleCreatePropertyFrame(hwndOwner: HWnd; x, y: Integer;
    lpszCaption: POleStr; cObjects: Integer; pObjects: Pointer;
    cPages: Integer; pPageCLSIDs: Pointer; lcid: TLCID; dwReserved: Longint;
    pvReserved: Pointer): HResult; stdcall external olepro32 name 'OleCreatePropertyFrame';


var
	LastError:String='';
implementation
uses Contnrs,sysutils,variants;

function FPS2RT (fps:Double):REFERENCE_TIME;
begin
	Result:=Round(10000000/fps);
end;
function FPS2NS (fps:Double):Cardinal;
begin
	Result:=Round(1000/fps);
end;


Function CreateGraphBuilder (out gb_gb:IGraphBuilder):boolean;
var
	hr:HRESULT;
begin
	hr:=CoCreateInstance(CLSID_FilterGraph,nil,1,IID_IGraphBuilder,gb_gb);
	if Failed(hr) then begin
		LastError:='Can''t create  graphbuilder ';
		result:=false;
		exit;
	end;
	result:=true;
end;

Function AddFilterToGraph (gb_gb:IGraphBuilder; guid: TGUID; fltname:String; out filter:IBaseFilter):boolean;
var
	hr:HRESULT;
begin
	if gb_gb=nil then begin
		Result:=false;
		exit;
	end;

	hr:=CoCreateInstance(guid,nil,1,IID_IBaseFilter,filter);
	if Failed(hr) then begin
		LastError:='Can''t create '+fltname;
		result:=false;
		exit;
	end;
	hr:=gb_gb.AddFilter(filter,'RENDER');
	if Failed(hr) then begin
		LastError:='Can''t add '+fltname;
		filter:=nil;
		result:=false;
		exit;
	end;
	result:=true;
end;

Procedure EnumPins (filter:IBaseFilter);
var
	ip:IEnumPins;
	id:PWideChar;
	ids:String;
	hr:HRESULT;
	pin:IPin;
	pd:_PinDirection;
begin
	hr:=filter.EnumPins (ip);
	if Failed(hr) then begin
		LastError:='Can''t enum pins';
		exit;
	end;

	LastError:='Pins list: '#13#10;
	pin:=nil;
	while (ip.Next(1,pin,nil)=s_OK) do begin
		pin.QueryId (id);
		ids:=id;
		CoTaskMemFree (id);
		pin.QueryDirection (pd);
		if (pd=PINDIR_INPUT) then begin
			LastError:=LastError+' INPUT: '+ids+#13#10;
		end else begin
			LastError:=LastError+' OUTPUT: '+ids+#13#10;
		end;
		pin:=nil;
	end;
	ip:=nil;
end;


Function FindPin (filter:IBaseFilter; pinname:String; out pin:IPin):boolean;
var
	hr:HRESULT;
	ip:IEnumPins;

	id:PWideChar;
	ids:String;
	pnm:WideString;
begin
	if (filter=nil) then begin
		Result:=false; exit;
	end;

	pnm:=pinname+#0;
	hr:=filter.FindPin(@pnm[1],pin);
	if Failed(hr) then begin
		hr:=filter.EnumPins (ip);
		if Failed(hr) or (ip=nil) then begin
			LastError:='Can''t enum pins';
			result:=false;
			exit;
		end;

		pin:=nil;
		while (ip.Next(1,pin,nil)=s_OK) do begin
			if (pin=nil) then break;
			pin.QueryId (id);
			if (id<>nil) then ids:=id else ids:='';
			if (ids=pinname) then begin
				CoTaskMemFree (id);
				break;
			end else begin
				CoTaskMemFree (id);
				pin:=nil;
			end;
		end;
		ip:=nil;
		result:=pin<>nil;
		if not result then LastError:='Can''t find pin '+pinname;
		exit;
	end;
	result:=true;
end;

//Type TPinEnum=function (pin:IPin):Boolean of object;
Function EnumPinsCB (filter:IBaseFilter; callback:TPinEnum):boolean;
var
	hr:HRESULT;
	ip:IEnumPins;

	pin:IPin;
begin
	result:=false;
	if filter=nil then exit;
	hr:=filter.EnumPins (ip);
	if Failed(hr) then begin
		LastError:='Can''t enum pins';
		exit;
	end;

	pin:=nil;
	while (ip.Next(1,pin,nil)=s_OK) do begin
		result:=true;
		if callback (pin) then break;
		pin:=nil;
	end;
	pin:=nil;
	ip:=nil;
end;

function ConnectPins (gb_gb:IGraphBuilder; flt_from:IBaseFilter; pin_from:String; flt_to:IBaseFilter; pin_to:string):boolean;
var
	p1,p2:IPin;
	hr:HRESULT;
begin
	if (gb_gb=nil) or (flt_from=nil) or (flt_to=nil) then begin
		Result:=false;
		exit;
	end;

	Result:=FindPin (flt_from,pin_from,p1);
	if not result then exit;
	Result:=FindPin (flt_to,pin_to,p2);
	if not result then begin
		p1:=nil;
		exit;
	end;
	hr:=gb_gb.Connect(p1,p2);
	p1:=nil;
	p2:=nil;
	if Failed(hr) then begin
		LastError:='Can''t connect';
		result:=false;
		exit;
	end;
	result:=true;
end;



constructor TBaseFilterHolder.Create(bf: IBaseFilter);
begin
	bfr:=bf;
end;
destructor TBaseFilterHolder.Destroy;
begin
	bfr:=nil;
end;

function EnumGraphCB (gb_gb:IGraphBuilder;cb:TGraphEnum):boolean;
var
	efi:IEnumFilters;
	hr:HRESULT;
	flt:IBaseFilter;
	g:TGUID;
begin
	result:=false;
	if gb_gb=nil then exit;

	hr:=gb_gb.EnumFilters (efi);
	if (failed(hr)) then begin
		LastError:='Can''t enum filters';
		exit;
	end;
	while (efi.Next (1,flt,nil)=s_OK) do begin
		flt.GetClassID (g);
		if cb(flt,@g) then break;
		flt:=nil;
	end;
	efi:=nil;
	result:=true;
end;

function FreeGraph (gb_gb:IGraphBuilder; keepguids:String):boolean;
var
	efi:IEnumFilters;
	hr:HRESULT;
	toremove:TObjectList;
	flt:IBaseFilter;
	g:TGUID;
	x,l:integer;
begin
	result:=false;
	if gb_gb=nil then exit;

	hr:=gb_gb.EnumFilters (efi);
	if (failed(hr)) then begin
		LastError:='Can''t enum filters';
		exit;
	end;
	toremove:=TObjectList.Create (true);
	while (efi.Next (1,flt,nil)=s_OK) do begin
		flt.GetClassID (g);
		if (keepguids<>'') and  (pos(GUIDToString(g),keepguids)=0) then toremove.Add (TBaseFilterHolder.Create(flt));
		flt:=nil;
	end;
	efi:=nil;
	l:=toremove.Count-1;
	for x:=0 to l do gb_gb.RemoveFilter (TBaseFilterHolder(toremove[x]).bfr);
	toremove.free;
end;

function DisconnectPin (gb_gb:IGraphBuilder;  flt:IBaseFilter; pin:String):boolean;
var
	p1:IPin;
	hr:HRESULT;
begin
	if (gb_gb=nil) or (flt=nil) then begin
		Result:=false;
		exit;
	end;
	Result:=FindPin (flt,pin,p1);
	if not result then exit;
	hr:=gb_gb.Disconnect(p1);
	p1:=nil;
	if Failed(hr) then begin
		LastError:='Can''t disconnect';
		result:=false;
		exit;
	end;
	result:=true;
end;

function StartGraph (gb_gb:IGraphBuilder; var isRuning:boolean):boolean;
var
	mc:IMediaControl;
begin
	if gb_gb=nil then begin
		Result:=false;
		exit;
	end;

	if isRuning then begin
		result:=true;
		exit;
	end;
	try
		mc:=gb_gb as IMediaControl;
	except
		Result:=false;
		exit;
	end;

	isRuning:=not Failed (mc.Run);
	mc:=nil;
	result:=isRuning;
end;


function StopGraph (gb_gb:IGraphBuilder; var isRuning:boolean):Boolean;
var
	mc:IMediaControl;
begin
	if gb_gb=nil then begin
		Result:=false;
		exit;
	end;

	if not isRuning then begin
		result:=true;
		exit;
	end;
	try
		mc:=gb_gb as IMediaControl;
	except
		Result:=false;
		exit;
	end;
	isRuning:=Failed (mc.Stop);
	mc:=nil;
	result:=not isRuning;
end;

Function StoreFltState (filename:String;flt:IBaseFilter;stmnm:string='flt'):boolean;
var
	ps:IPersistStream;
	st:IStorage;
	stm:IStream;
	fn:WideString;
	stmnmw:WideString;
begin
	result:=false;
	try
		ps:=flt as IPersistStream;
	except
		exit;
	end;
	fn:=filename+#0#0;
	stmnmw:=stmnm+#0#0;
	if (ps<>nil) then begin
		if failed(StgCreateDocfile (@fn[1],STGM_DIRECT or STGM_READWRITE or STGM_SHARE_EXCLUSIVE or STGM_CREATE,0,st)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
		if failed(st.CreateStream (@stmnmw[1],STGM_DIRECT or STGM_READWRITE or STGM_SHARE_EXCLUSIVE or STGM_CREATE,0,0,stm)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
		if failed(ps.Save (stm,true)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
		stm.Commit (0);
		st.Commit (0);

		ps:=nil;
		stm:=nil;
		st:=nil;
	end else exit;
	ps:=nil;
	result:=true;
end;

Function LoadFltState (filename:String;flt:IBaseFilter;stmnm:string='flt'):boolean;
var
	ps:IPersistStream;
	st:IStorage;
	stm:IStream;
	fn:WideString;
	stmnmw:WideString;
begin
	result:=false;
	try
		ps:=flt as IPersistStream;
	except
		exit;
	end;
	fn:=filename+#0#0;
	stmnmw:=stmnm+#0#0;
	if (ps<>nil) then begin
		if failed(StgOpenStorage (@fn[1],nil,STGM_DIRECT or STGM_READ or STGM_SHARE_EXCLUSIVE ,nil,0,st)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
		if failed(st.OpenStream (@stmnmw[1],nil,STGM_DIRECT or STGM_READ or STGM_SHARE_EXCLUSIVE,0,stm)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
		if failed(ps.Load (stm)) then begin
			ps:=nil;
			stm:=nil;
			st:=nil;
			exit;
		end;
//		stm.Commit (0);
//		st.Commit (0);

		ps:=nil;
		stm:=nil;
		st:=nil;
	end else exit;
	ps:=nil;
	result:=true;
end;


//HRESULT AddToRot(IUnknown *pUnkGraph, DWORD *pdwRegister)
function publish_graph (gb:IGraphBuilder):HResult;
var
	pMoniker:IMoniker;
	pROT:IRunningObjectTable;
	wsz:WideString;
	hr:HRESULT;
	reg:cardinal;
begin

	if (FAILED(GetRunningObjectTable(0, pROT))) then begin
		result:=E_FAIL;
		exit;
	end;
	wsz:='FilterGraph '+IntToHex(integer(pointer(gb)),0)+' pid '+IntToHex(GetCurrentProcessId(),8)+#0#0;
//	StringCchPrintfW(wsz, STRING_LENGTH, L"FilterGraph %08x pid %08x", (DWORD_PTR)pUnkGraph, GetCurrentProcessId());

	hr := CreateItemMoniker('!', @wsz[1], &pMoniker);
	if (SUCCEEDED(hr)) then begin
		hr := pROT.Register(ROTFLAGS_REGISTRATIONKEEPSALIVE, gb, pMoniker, reg);
		pMoniker:=nil;
	end;
	pROT:=nil;
	result:=hr;
end;

function ShowPropPage (flt:IBaseFilter; ppn:String='PROPS';wnd:HWND=0):boolean;
begin
	if (flt<>nil ) then begin
		result:=Not failed( OleCreatePropertyFrame (wnd,0,0,'PROP',1,@flt,0,nil,0,0,nil));
	end else begin
		Result:=false;
	end;
end;


Procedure EnumDevices (cat:TGUID; listto:TStrings);
var
	de:ICreateDevEnum;
	me:IEnumMoniker;
	m:IMoniker;
	g:TGUID;
	pb:IPropertyBag;
	fn:Variant;
	fns:String;
	dummy:LongWord;
begin
	CoCreateInstance (CLSID_SystemDeviceEnum,nil,CLSCTX_INPROC_SERVER,IID_ICreateDevEnum,de);
	if (de.CreateClassEnumerator (cat,me,0)<>S_OK) then begin
		de:=nil;
		exit;
	end;
	de:=nil;
	while (me.Next (1,m,dummy)=s_ok) do begin
		m.GetClassID (g);
		m.BindToStorage (nil, nil, IPropertyBag,pb);
		if not failed(pb.Read ('FriendlyName',fn,nil)) then begin
			fns:=fn;
			listto.Add (fns);
		end;
		pb:=nil;
		m:=nil;
	end;
	me:=nil;
end;


Function FindDeviceByName (cat:TGUID; name:String):IBaseFilter;
var
	de:ICreateDevEnum;
	me:IEnumMoniker;
	m:IMoniker;
	g:TGUID;
	pb:IPropertyBag;
	fn:Variant;
	fns:String;
	dummy:longWord;
begin
	Result:=nil;
	CoCreateInstance (CLSID_SystemDeviceEnum,nil,CLSCTX_INPROC_SERVER,IID_ICreateDevEnum,de);
	if (de.CreateClassEnumerator (cat,me,0)<>S_OK) then begin
		de:=nil;
		exit;
	end;
	de:=nil;
	while (me.Next (1,m,dummy)=s_ok) do begin
		m.GetClassID (g);
		m.BindToStorage (nil, nil, IPropertyBag,pb);
		if not failed(pb.Read ('FriendlyName',fn,nil)) then begin
			fns:=fn;
			if fns=name then begin
				if  not failed(m.BindToObject (nil,nil,IBaseFilter,result)) then begin
					m:=nil;
					break;
				end else Result:=nil;
			end;
		end;
		pb:=nil;
		m:=nil;
	end;
	me:=nil;
end;



initialization
CoInitialize(Nil);
end.
