param(
    [string]$DeviceName = 'VC-002Pro '
)

$ErrorActionPreference = 'Stop'

# COM activation, interface binding, enumeration, and property reads stay in
# strongly typed C#. The helper exposes Get/GetRange only; it has no Set call.
$readerSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Threading;

[ComImport]
[Guid("29840822-5B84-11D0-BD3B-00A0C911CE86")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IProcAmpCreateDevEnum
{
    [PreserveSig]
    int CreateClassEnumerator(ref Guid deviceClass, out IEnumMoniker monikers, int flags);
}

[ComImport]
[Guid("55272A00-42CB-11CE-8135-00AA004BB851")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IProcAmpPropertyBag
{
    [PreserveSig]
    int Read([MarshalAs(UnmanagedType.LPWStr)] string propertyName,
             [In, Out, MarshalAs(UnmanagedType.Struct)] ref object value,
             IntPtr errorLog);
}

[ComImport]
[Guid("C6E13360-30AC-11D0-A18C-00A0C9118956")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IProcAmpVideoProcAmp
{
    [PreserveSig]
    int GetRange(int property, out int minimum, out int maximum,
                 out int steppingDelta, out int defaultValue, out int capabilityFlags);

    // Required vtable slot between GetRange and Get. Never called by this tool.
    [PreserveSig]
    int UnusedSet(int property, int value, int flags);

    [PreserveSig]
    int Get(int property, out int value, out int flags);
}

public static class DirectShowProcAmpReader
{
    private const int VideoProcAmpFlagsAuto = 1;
    private const int VideoProcAmpFlagsManual = 2;

    private static readonly KeyValuePair<string, int>[] Properties = {
        new KeyValuePair<string, int>("Brightness", 0),
        new KeyValuePair<string, int>("Contrast", 1),
        new KeyValuePair<string, int>("Hue", 2),
        new KeyValuePair<string, int>("Saturation", 3),
        new KeyValuePair<string, int>("Sharpness", 4),
        new KeyValuePair<string, int>("Gamma", 5),
        new KeyValuePair<string, int>("ColorEnable", 6),
        new KeyValuePair<string, int>("WhiteBalance", 7),
        new KeyValuePair<string, int>("BacklightCompensation", 8),
        new KeyValuePair<string, int>("Gain", 9),
    };

    public static object ReadExactFriendlyName(string exactName)
    {
        object result = null;
        Exception error = null;
        Thread thread = new Thread(() => {
            try { result = ReadOnSta(exactName); }
            catch (Exception ex) { error = ex; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (error != null) throw new InvalidOperationException(error.Message, error);
        return result;
    }

    private static object ReadOnSta(string exactName)
    {
        Guid systemDeviceEnumClsid = new Guid("62BE5D10-60EB-11D0-BD3B-00A0C911CE86");
        Guid videoInputCategory = new Guid("860BB310-5D01-11D0-BD3B-00A0C911CE86");
        Guid baseFilterIid = new Guid("56A86895-0AD4-11CE-B03A-0020AF0BA770");
        Guid propertyBagIid = new Guid("55272A00-42CB-11CE-8135-00AA004BB851");

        object deviceEnumObject = null;
        IEnumMoniker enumerator = null;
        List<object> devices = new List<object>();
        try
        {
            Type enumType = Type.GetTypeFromCLSID(systemDeviceEnumClsid, true);
            deviceEnumObject = Activator.CreateInstance(enumType);
            IProcAmpCreateDevEnum deviceEnum = (IProcAmpCreateDevEnum)deviceEnumObject;
            int enumHr = deviceEnum.CreateClassEnumerator(ref videoInputCategory, out enumerator, 0);
            if (enumHr != 0 || enumerator == null)
                throw new COMException("DirectShow video input enumeration returned no category.", enumHr);

            IMoniker[] batch = new IMoniker[1];
            while (enumerator.Next(1, batch, IntPtr.Zero) == 0)
            {
                IMoniker moniker = batch[0];
                object bagObject = null;
                object filterObject = null;
                try
                {
                    moniker.BindToStorage(null, null, ref propertyBagIid, out bagObject);
                    IProcAmpPropertyBag propertyBag = (IProcAmpPropertyBag)bagObject;
                    object nameObject = null;
                    int nameHr = propertyBag.Read("FriendlyName", ref nameObject, IntPtr.Zero);
                    if (nameHr < 0) continue;
                    string friendlyName = Convert.ToString(nameObject);
                    if (!String.Equals(friendlyName, exactName, StringComparison.Ordinal)) continue;
                    object devicePathObject = null;
                    int devicePathHr = propertyBag.Read("DevicePath", ref devicePathObject, IntPtr.Zero);
                    string devicePath = devicePathHr >= 0 ? Convert.ToString(devicePathObject) : null;

                    string displayName;
                    moniker.GetDisplayName(null, null, out displayName);
                    moniker.BindToObject(null, null, ref baseFilterIid, out filterObject);
                    IProcAmpVideoProcAmp procAmp = null;
                    string interfaceError = null;
                    try { procAmp = filterObject as IProcAmpVideoProcAmp; }
                    catch (Exception ex) { interfaceError = ex.Message; }

                    Dictionary<string, object> properties = new Dictionary<string, object>();
                    foreach (KeyValuePair<string, int> property in Properties)
                        properties[property.Key] = ReadProperty(procAmp, property.Value);

                    devices.Add(new Dictionary<string, object> {
                        { "friendly_name", friendlyName },
                        { "device_path", devicePath },
                        { "moniker_display_name", displayName },
                        { "interface_supported", procAmp != null },
                        { "interface_error", interfaceError },
                        { "properties", properties },
                    });
                }
                finally
                {
                    ReleaseCom(filterObject);
                    ReleaseCom(bagObject);
                    ReleaseCom(moniker);
                    batch[0] = null;
                }
            }
        }
        finally
        {
            ReleaseCom(enumerator);
            ReleaseCom(deviceEnumObject);
        }

        if (devices.Count == 0)
            return new Dictionary<string, object> {
                { "device_name_requested", exactName },
                { "found", false },
                { "read_only", true },
                { "message", "No video input with this exact FriendlyName was found." },
            };

        return new Dictionary<string, object> {
            { "device_name_requested", exactName },
            { "found", true },
            { "read_only", true },
            { "note", "Values use device-specific units. Only IAMVideoProcAmp::Get and GetRange are called." },
            { "devices", devices },
        };
    }

    private static Dictionary<string, object> ReadProperty(IProcAmpVideoProcAmp procAmp, int property)
    {
        int min = 0, max = 0, step = 0, defaultValue = 0, rangeFlags = 0;
        int rangeHr = procAmp == null ? unchecked((int)0x80004002) :
            procAmp.GetRange(property, out min, out max, out step, out defaultValue, out rangeFlags);
        int current = 0, currentFlags = 0;
        int getHr = procAmp == null ? unchecked((int)0x80004002) :
            procAmp.Get(property, out current, out currentFlags);

        List<string> capabilityControl = new List<string>();
        if (rangeHr >= 0 && (rangeFlags & VideoProcAmpFlagsAuto) != 0) capabilityControl.Add("auto");
        if (rangeHr >= 0 && (rangeFlags & VideoProcAmpFlagsManual) != 0) capabilityControl.Add("manual");
        object currentControl = null;
        if (getHr >= 0)
            currentControl = (currentFlags & VideoProcAmpFlagsAuto) != 0 ? "auto" :
                ((currentFlags & VideoProcAmpFlagsManual) != 0 ? "manual" : "unknown");

        return new Dictionary<string, object> {
            { "supported", rangeHr >= 0 || getHr >= 0 },
            { "current", getHr >= 0 ? (object)current : null },
            { "current_flags", getHr >= 0 ? (object)currentFlags : null },
            { "current_control", currentControl },
            { "minimum", rangeHr >= 0 ? (object)min : null },
            { "maximum", rangeHr >= 0 ? (object)max : null },
            { "step", rangeHr >= 0 ? (object)step : null },
            { "default", rangeHr >= 0 ? (object)defaultValue : null },
            { "capability_flags", rangeHr >= 0 ? (object)rangeFlags : null },
            { "capability_control", capabilityControl },
            { "get_hresult", HResult(getHr) },
            { "get_range_hresult", HResult(rangeHr) },
        };
    }

    private static string HResult(int hr) { return "0x" + unchecked((uint)hr).ToString("X8"); }

    private static void ReleaseCom(object value)
    {
        if (value != null && Marshal.IsComObject(value)) Marshal.FinalReleaseComObject(value);
    }
}
'@

try {
    Add-Type -TypeDefinition $readerSource -ErrorAction Stop
    $result = [DirectShowProcAmpReader]::ReadExactFriendlyName($DeviceName)
    $result | ConvertTo-Json -Depth 8
} catch {
    [ordered]@{
        device_name_requested = $DeviceName
        found = $false
        read_only = $true
        error = $_.Exception.Message
    } | ConvertTo-Json -Depth 5
    exit 1
}
