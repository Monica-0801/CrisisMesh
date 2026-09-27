namespace CrisisMeshBackend.Models;

public class SosIncident
{
    public int Id { get; set; }
    public string? ClientEventId { get; set; }
    public string DeviceId { get; set; } = "crisismesh-android";
    public string Message { get; set; } = string.Empty;
    public string? VoiceTranscript { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? PhotoPath { get; set; }
    public string RelayMode { get; set; } = "mesh";
    public string Status { get; set; } = "queued";
    public string DangerType { get; set; } = "General emergency";
    public int Priority { get; set; } = 3;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
