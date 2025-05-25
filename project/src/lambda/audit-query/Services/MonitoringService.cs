using Amazon.CloudWatch;
using Amazon.CloudWatch.Model;
using Amazon.XRay.Recorder.Core;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace AuditQuery.Services
{
    public class MonitoringService : IMonitoringService
    {
        private readonly IAmazonCloudWatch _cloudWatch;
        private readonly ILogger<MonitoringService> _logger;
        private readonly string _environment;
        private readonly string _serviceName;

        public MonitoringService(
            IAmazonCloudWatch cloudWatch,
            ILogger<MonitoringService> logger,
            string environment,
            string serviceName)
        {
            _cloudWatch = cloudWatch ?? throw new ArgumentNullException(nameof(cloudWatch));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
            _environment = environment ?? throw new ArgumentNullException(nameof(environment));
            _serviceName = serviceName ?? throw new ArgumentNullException(nameof(serviceName));
        }

        public async Task TrackQueryMetrics(
            string userId,
            string? systemId,
            int resultCount,
            long executionTimeMs,
            bool isSuccess)
        {
            try
            {
                var dimensions = new List<Dimension>
                {
                    new Dimension { Name = "Environment", Value = _environment },
                    new Dimension { Name = "Service", Value = _serviceName },
                    new Dimension { Name = "UserId", Value = userId }
                };

                if (!string.IsNullOrEmpty(systemId))
                {
                    dimensions.Add(new Dimension { Name = "SystemId", Value = systemId });
                }

                var metrics = new List<MetricDatum>
                {
                    new MetricDatum
                    {
                        MetricName = "QueryExecutionTime",
                        Value = executionTimeMs,
                        Unit = StandardUnit.Milliseconds,
                        Dimensions = dimensions
                    },
                    new MetricDatum
                    {
                        MetricName = "QueryResultCount",
                        Value = resultCount,
                        Unit = StandardUnit.Count,
                        Dimensions = dimensions
                    },
                    new MetricDatum
                    {
                        MetricName = "QuerySuccess",
                        Value = isSuccess ? 1 : 0,
                        Unit = StandardUnit.Count,
                        Dimensions = dimensions
                    }
                };

                var request = new PutMetricDataRequest
                {
                    Namespace = "AuditSystem",
                    MetricData = metrics
                };

                await _cloudWatch.PutMetricDataAsync(request);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error tracking metrics");
            }
        }

        public void TrackXRaySegment(string operation, Action action)
        {
            try
            {
                AWSXRayRecorder.Instance.BeginSubsegment(operation);
                action();
            }
            catch (Exception ex)
            {
                AWSXRayRecorder.Instance.AddException(ex);
                throw;
            }
            finally
            {
                AWSXRayRecorder.Instance.EndSubsegment();
            }
        }

        public async Task<T> TrackXRaySegmentAsync<T>(string operation, Func<Task<T>> action)
        {
            try
            {
                AWSXRayRecorder.Instance.BeginSubsegment(operation);
                return await action();
            }
            catch (Exception ex)
            {
                AWSXRayRecorder.Instance.AddException(ex);
                throw;
            }
            finally
            {
                AWSXRayRecorder.Instance.EndSubsegment();
            }
        }
    }
} 