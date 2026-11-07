using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Xml;

namespace QuickScripts {
    public class WifiProfile {
        public string Name { get; set; }
        public string Interface { get; set; }
        public string Password { get; set; }
        public string Status { get; set; }
    }

    public static class WifiReader {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct InterfaceInfo {
            public Guid Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string Description;
            public int State;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct ProfileInfo {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
            public string Name;
            public uint Flags;
        }

        [DllImport("wlanapi.dll")]
        static extern uint WlanOpenHandle(
            uint version, IntPtr reserved, out uint negotiated,
            out IntPtr handle);

        [DllImport("wlanapi.dll")]
        static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);

        [DllImport("wlanapi.dll")]
        static extern void WlanFreeMemory(IntPtr memory);

        [DllImport("wlanapi.dll")]
        static extern uint WlanEnumInterfaces(
            IntPtr handle, IntPtr reserved, out IntPtr list);

        [DllImport("wlanapi.dll")]
        static extern uint WlanGetProfileList(
            IntPtr handle, ref Guid id, IntPtr reserved, out IntPtr list);

        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)]
        static extern uint WlanGetProfile(
            IntPtr handle, ref Guid id, string name, IntPtr reserved,
            out IntPtr xml, ref uint flags, out uint access);

        static void Check(uint result) {
            if (result != 0) {
                throw new Win32Exception((int)result);
            }
        }

        public static WifiProfile[] Read(string filter) {
            IntPtr handle = IntPtr.Zero;
            IntPtr interfaces = IntPtr.Zero;
            var output = new List<WifiProfile>();
            uint negotiated;
            Check(WlanOpenHandle(2, IntPtr.Zero, out negotiated, out handle));

            try {
                Check(WlanEnumInterfaces(handle, IntPtr.Zero, out interfaces));
                int count = Marshal.ReadInt32(interfaces);
                int size = Marshal.SizeOf(typeof(InterfaceInfo));
                for (int i = 0; i < count; i++) {
                    var address = IntPtr.Add(interfaces, 8 + i * size);
                    var info = (InterfaceInfo)Marshal.PtrToStructure(
                        address, typeof(InterfaceInfo));
                    output.AddRange(ReadInterface(handle, info, filter));
                }
            } finally {
                if (interfaces != IntPtr.Zero) WlanFreeMemory(interfaces);
                WlanCloseHandle(handle, IntPtr.Zero);
            }
            return output.ToArray();
        }

        static List<WifiProfile> ReadInterface(
            IntPtr handle, InterfaceInfo info, string filter) {
            IntPtr profiles = IntPtr.Zero;
            var output = new List<WifiProfile>();
            try {
                Check(WlanGetProfileList(
                    handle, ref info.Id, IntPtr.Zero, out profiles));
                int count = Marshal.ReadInt32(profiles);
                int size = Marshal.SizeOf(typeof(ProfileInfo));
                for (int i = 0; i < count; i++) {
                    var address = IntPtr.Add(profiles, 8 + i * size);
                    var profile = (ProfileInfo)Marshal.PtrToStructure(
                        address, typeof(ProfileInfo));
                    bool matches = String.IsNullOrEmpty(filter) ||
                        String.Equals(profile.Name, filter,
                            StringComparison.OrdinalIgnoreCase);
                    if (matches) {
                        output.Add(ReadProfile(handle, info, profile.Name));
                    }
                }
            } finally {
                if (profiles != IntPtr.Zero) WlanFreeMemory(profiles);
            }
            return output;
        }

        static WifiProfile ReadProfile(
            IntPtr handle, InterfaceInfo info, string name) {
            var item = new WifiProfile {
                Name = name,
                Interface = info.Description
            };
            IntPtr xml = IntPtr.Zero;
            uint flags = 4;
            uint access;
            try {
                uint result = WlanGetProfile(
                    handle, ref info.Id, name, IntPtr.Zero,
                    out xml, ref flags, out access);
                if (result != 0) {
                    item.Status = new Win32Exception((int)result).Message;
                } else {
                    ReadSharedKey(item, Marshal.PtrToStringUni(xml));
                }
            } finally {
                if (xml != IntPtr.Zero) WlanFreeMemory(xml);
            }
            return item;
        }

        static void ReadSharedKey(WifiProfile item, string xml) {
            var document = new XmlDocument();
            document.XmlResolver = null;
            document.LoadXml(xml);

            var sharedKey = document.SelectSingleNode(
                "/*[local-name()='WLANProfile']/*[local-name()='MSM']" +
                "/*[local-name()='security']/*[local-name()='sharedKey']");
            var key = sharedKey == null ? null :
                sharedKey.SelectSingleNode("*[local-name()='keyMaterial']");
            var encrypted = sharedKey == null ? null :
                sharedKey.SelectSingleNode("*[local-name()='protected']");

            if (key == null) {
                item.Status =
                    "No stored shared key (open or enterprise profile)";
            } else if (encrypted != null && String.Equals(
                encrypted.InnerText, "true",
                StringComparison.OrdinalIgnoreCase)) {
                item.Status = "Key protected; run as administrator to reveal";
            } else {
                item.Password = key.InnerText;
                item.Status = "Available";
            }
        }
    }
}
