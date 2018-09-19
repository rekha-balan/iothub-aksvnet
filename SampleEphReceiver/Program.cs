// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.

namespace SampleEphReceiver
{
    using System;
    using System.Threading.Tasks;
    using Microsoft.Azure.EventHubs;
    using Microsoft.Azure.EventHubs.Processor;

    public class Program
    {
        private readonly static string EventHubConnectionString = System.Environment.GetEnvironmentVariable("EVENT_HUB_CONNECTION_STRING");
        private readonly static string EventHubName = System.Environment.GetEnvironmentVariable("EVENT_HUB_NAME");
        private readonly static string StorageContainerName = System.Environment.GetEnvironmentVariable("STORAGE_CONTAINER_NAME");
        private readonly static string StorageAccountName = System.Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_NAME");
        private readonly static string StorageAccountKey = System.Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_KEY");

        private static readonly string StorageConnectionString = string.Format("DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1}", StorageAccountName, StorageAccountKey);

        public static void Main(string[] args)
        {
            MainAsync(args).GetAwaiter().GetResult();
        }

        private static async Task MainAsync(string[] args)
        {
            Console.WriteLine("Registering EventProcessor...");

            var eventProcessorHost = new EventProcessorHost(
                EventHubName,
                PartitionReceiver.DefaultConsumerGroupName,
                EventHubConnectionString,
                StorageConnectionString,
                StorageContainerName);

            // Registers the Event Processor Host and starts receiving messages
            await eventProcessorHost.RegisterEventProcessorAsync<SimpleEventProcessor>();

            Console.WriteLine("Receiving. Press enter key to stop worker.");
            Console.ReadLine();

            // Disposes of the Event Processor Host
            await eventProcessorHost.UnregisterEventProcessorAsync();
        }
    }
}
