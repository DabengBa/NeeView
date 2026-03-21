//#define LOCAL_DEBUG

using NeeLaboratory.Generators;
using NeeLaboratory.Threading.Jobs;
using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace NeeView
{
    /// <summary>
    /// 非同期処理をJOBとして順番に実行する
    /// </summary>
    /// <remake>
    /// 時間のかかる初期化処理を非同期でおこなうときに使用する
    /// </remake>
    [LocalDebug]
    public partial class ProcessJobEngine : ProgressTaskJobEngine<ProgressContext>
    {
        public static Lazy<ProcessJobEngine> _current = new();
        public static ProcessJobEngine Current => _current.Value;
        private string? _currentJobName;
        private int _queuedJobsCount;
        private int _completedJobsCount;

        public string? CurrentJobName
        {
            get => _currentJobName;
            private set => SetProperty(ref _currentJobName, value);
        }

        public int QueuedJobsCount => _queuedJobsCount;
        public int CompletedJobsCount => _completedJobsCount;

        public JobOperation<int> AddJob(string name, Action job)
        {
            Interlocked.Increment(ref _queuedJobsCount);
            TraceStartupJob("queue", name);
            return AddJob(InnerJob);

            async ValueTask InnerJob(IProgress<ProgressContext>? progress, CancellationToken token)
            {
                CurrentJobName = name;
                TraceStartupJob("start", name);
                try
                {
                    progress?.Report(new ProgressContext(name));
                    job.Invoke();
                }
                finally
                {
                    Interlocked.Increment(ref _completedJobsCount);
                    TraceStartupJob("end", name);
                    CurrentJobName = null;
                }
            }
        }

        public JobOperation<int> AddJob(string name, Func<CancellationToken, ValueTask> job)
        {
            Interlocked.Increment(ref _queuedJobsCount);
            TraceStartupJob("queue", name);
            return AddJob(InnerJob);

            async ValueTask InnerJob(IProgress<ProgressContext>? progress, CancellationToken token)
            {
                CurrentJobName = name;
                TraceStartupJob("start", name);
                try
                {
                    progress?.Report(new ProgressContext(name));
                    await job.Invoke(token);
                }
                finally
                {
                    Interlocked.Increment(ref _completedJobsCount);
                    TraceStartupJob("end", name);
                    CurrentJobName = null;
                }
            }
        }

        private void TraceStartupJob(string phase, string name)
        {
            if (!App.Current.Stopwatch.IsRunning || App.Current.Stopwatch.ElapsedMilliseconds > 10000) return;

            Trace.WriteLine($"Startup.ProcessJobEngine.Job|phase={phase}|name={name}|pending={PendingJobsCount}|processing={(IsProcessing ? 1 : 0)}|busy={(IsBusy ? 1 : 0)}|queued={QueuedJobsCount}|completed={CompletedJobsCount}|current={CurrentJobName}");
        }
    }
}
