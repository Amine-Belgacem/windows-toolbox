using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;

namespace QuickScripts {
    // The execution-state request belongs to one dedicated thread.
    public sealed class AwakeSession : IDisposable {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern uint SetThreadExecutionState(uint flags);

        readonly ManualResetEvent stop = new ManualResetEvent(false);
        readonly ManualResetEvent ready = new ManualResetEvent(false);
        readonly Thread worker;
        Exception error;

        public AwakeSession(bool display) {
            worker = new Thread(() => Run(display));
            worker.IsBackground = true;
            worker.Start();
            ready.WaitOne();

            if (error != null) {
                Dispose();
                throw error;
            }
        }

        void Run(bool display) {
            try {
                uint flags = 0x80000001u | (display ? 2u : 0u);
                if (SetThreadExecutionState(flags) == 0) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                ready.Set();
                stop.WaitOne();
            } catch (Exception exception) {
                error = exception;
                ready.Set();
            } finally {
                SetThreadExecutionState(0x80000000u);
            }
        }

        public void Dispose() {
            stop.Set();
            worker.Join();
            ready.Dispose();
            stop.Dispose();
        }
    }
}
