using System.Globalization;
using CrisisMeshBackend.Models;
using Microsoft.EntityFrameworkCore;

namespace CrisisMeshBackend.Data;

public sealed class DatasetImporter(
    CrisisMeshDbContext db,
    IConfiguration configuration,
    ILogger<DatasetImporter> logger)
{
    public async Task ImportAsync(CancellationToken cancellationToken)
    {
        var importEnabled = configuration.GetValue("Dataset:ImportOnStartup", true);
        if (!importEnabled)
        {
            return;
        }

        var configuredPath = configuration["Dataset:CsvPath"];
        if (string.IsNullOrWhiteSpace(configuredPath))
        {
            logger.LogWarning("Dataset import skipped because Dataset:CsvPath is not configured.");
            return;
        }

        if (!File.Exists(configuredPath))
        {
            logger.LogWarning("Dataset import skipped because CSV file was not found at {Path}.", configuredPath);
            return;
        }

        var existingIds = await db.DatasetIncidents
            .Select(x => x.IncidentId)
            .ToHashSetAsync(cancellationToken);
        var imported = 0;
        var skipped = 0;

        await using var stream = File.OpenRead(configuredPath);
        using var reader = new StreamReader(stream);
        var header = await reader.ReadLineAsync(cancellationToken);
        if (header is null)
        {
            logger.LogWarning("Dataset import skipped because the CSV file is empty.");
            return;
        }

        var expectedHeader =
            "incident_id,timestamp,emergency_type,message,latitude,longitude,location_name," +
            "severity,people_affected,photo_attached,photo_path,status,retry_count," +
            "network_available,created_at,last_attempt_at,server_incident_id";
        if (!string.Equals(header, expectedHeader, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("The dataset CSV header does not match the expected schema.");
        }

        var lineNumber = 1;
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            lineNumber++;
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            try
            {
                var values = ParseCsvLine(line);
                if (values.Count != 17)
                {
                    throw new InvalidDataException($"Expected 17 columns, found {values.Count}.");
                }

                var incidentId = Required(values[0], "incident_id");
                if (existingIds.Contains(incidentId))
                {
                    skipped++;
                    continue;
                }

                db.DatasetIncidents.Add(new DatasetIncident
                {
                    IncidentId = incidentId,
                    Timestamp = ParseDate(values[1], "timestamp"),
                    EmergencyType = Required(values[2], "emergency_type"),
                    Message = Required(values[3], "message"),
                    Latitude = ParseDouble(values[4], "latitude"),
                    Longitude = ParseDouble(values[5], "longitude"),
                    LocationName = Required(values[6], "location_name"),
                    Severity = Required(values[7], "severity"),
                    PeopleAffected = ParseInt(values[8], "people_affected"),
                    PhotoAttached = ParseBool(values[9], "photo_attached"),
                    PhotoPath = Nullable(values[10]),
                    Status = Required(values[11], "status"),
                    RetryCount = ParseInt(values[12], "retry_count"),
                    NetworkAvailable = ParseBool(values[13], "network_available"),
                    CreatedAt = ParseDate(values[14], "created_at"),
                    LastAttemptAt = NullableDate(values[15]),
                    ServerIncidentId = Nullable(values[16]),
                });
                existingIds.Add(incidentId);
                imported++;
            }
            catch (Exception exception) when (exception is FormatException or InvalidDataException)
            {
                throw new InvalidDataException(
                    $"Invalid dataset row at line {lineNumber}: {exception.Message}",
                    exception);
            }
        }

        await db.SaveChangesAsync(cancellationToken);
        logger.LogInformation(
            "Dataset import completed. Imported {Imported} records and skipped {Skipped} existing records.",
            imported,
            skipped);
    }

    private static string Required(string value, string field)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new InvalidDataException($"{field} is required.")
            : value;
    }

    private static string? Nullable(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : value;

    private static DateTime ParseDate(string value, string field) =>
        DateTime.Parse(
            Required(value, field),
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeLocal);

    private static DateTime? NullableDate(string value) =>
        string.IsNullOrWhiteSpace(value) ? null : ParseDate(value, "last_attempt_at");

    private static double ParseDouble(string value, string field) =>
        double.Parse(Required(value, field), CultureInfo.InvariantCulture);

    private static int ParseInt(string value, string field) =>
        int.Parse(Required(value, field), CultureInfo.InvariantCulture);

    private static bool ParseBool(string value, string field) =>
        bool.Parse(Required(value, field));

    private static List<string> ParseCsvLine(string line)
    {
        var values = new List<string>();
        var value = new System.Text.StringBuilder();
        var quoted = false;

        for (var index = 0; index < line.Length; index++)
        {
            var character = line[index];
            if (character == '"')
            {
                if (quoted && index + 1 < line.Length && line[index + 1] == '"')
                {
                    value.Append('"');
                    index++;
                }
                else
                {
                    quoted = !quoted;
                }
            }
            else if (character == ',' && !quoted)
            {
                values.Add(value.ToString());
                value.Clear();
            }
            else
            {
                value.Append(character);
            }
        }

        if (quoted)
        {
            throw new InvalidDataException("Unclosed quoted CSV value.");
        }

        values.Add(value.ToString());
        return values;
    }
}
