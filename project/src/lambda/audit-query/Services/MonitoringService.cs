using Amazon.CloudWatch;
using Amazon.CloudWatch.Model;
using Amazon.XRay.Recorder.Core;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace AuditQuery.Services
{
    /// <summary>
    /// Service for monitoring and observability of the audit query system.
    /// Handles CloudWatch metrics and X-Ray tracing for performance monitoring and debugging.
    /// </summary>
    public class MonitoringService : IMonitoringService
    {
        private readonly IAmazonCloudWatch _cloudWatch;
        private readonly ILogger<MonitoringService> _logger;
        private readonly string _environment;
        private readonly string _serviceName;

        /// <summary>
        /// Initializes the monitoring service with required AWS services and configuration.
        /// </summary>
        /// <param name="cloudWatch">CloudWatch client for metrics</param>
        /// <param name="logger">Logger for monitoring events</param>
        /// <param name="environment">Current environment (dev/staging/prod)</param>
        /// <param name="serviceName">Name of the service for metric dimensions</param>
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

        /// <summary>
        /// Tracks query performance metrics in CloudWatch.
        /// Records execution time, result count, and success status for each query.
        /// </summary>
        public async Task TrackQueryMetrics(
            string userId,
            string? systemId,
            int resultCount,
            long executionTimeMs,
            bool isSuccess)
        {
            try
            {
                // Define metric dimensions for filtering and grouping
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

                // Create metrics for different aspects of query performance
                var metrics = new List<MetricDatum>
                {
                    // Track query execution time for performance monitoring
                    new MetricDatum
                    {
                        MetricName = "QueryExecutionTime",
                        Value = executionTimeMs,
                        Unit = StandardUnit.Milliseconds,
                        Dimensions = dimensions
                    },
                    // Track number of results for capacity planning
                    new MetricDatum
                    {
                        MetricName = "QueryResultCount",
                        Value = resultCount,
                        Unit = StandardUnit.Count,
                        Dimensions = dimensions
                    },
                    // Track success rate for reliability monitoring
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

        /// <summary>
        /// Wraps a synchronous operation with X-Ray tracing.
        /// Records execution time and any exceptions that occur.
        /// </summary>
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

        /// <summary>
        /// Wraps an asynchronous operation with X-Ray tracing.
        /// Records execution time and any exceptions that occur.
        /// </summary>
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