# https://docs.microsoft.com/en-us/azure/event-hubs/event-hubs-dotnet-standard-getstarted-receive-eph
FROM microsoft/dotnet:2.0-sdk AS build-env
WORKDIR /app

COPY *.csproj ./
RUN dotnet restore

COPY . ./
RUN dotnet publish -c Release -o out

FROM microsoft/dotnet:2.0-runtime
WORKDIR /app
COPY --from=build-env /app/out ./

CMD ["dotnet", "SampleEphReceiver.dll"]
