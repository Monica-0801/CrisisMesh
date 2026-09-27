namespace CrisisMeshBackend.Models;

public class DatasetIncident
{
    public int Id { get; set; }
    public string IncidentId { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public string EmergencyType { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string LocationName { get; set; } = string.Empty;
    public string Severity { get; set; } = string.Empty;
    public int PeopleAffected { get; set; }
    public bool PhotoAttached { get; set; }
    public string? PhotoPath { get; set; }
    public string Status { get; set; } = string.Empty;
    public int RetryCount { get; set; }
    public bool NetworkAvailable { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? LastAttemptAt { get; set; }
    public string? ServerIncidentId { get; set; }
}
