using System;
using System.Runtime.InteropServices;

namespace QuickScripts {
    public static class EnvironmentBroadcast {
        [DllImport("user32.dll", CharSet = CharSet.Unicode,
            SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr window, uint message, UIntPtr parameter, string text,
            uint flags, uint timeout, out UIntPtr result);
    }
}
