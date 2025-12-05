using System.IO.Compression;

namespace DbTool.Infrastructure.Services;

/// <summary>
/// Interface for compression services.
/// </summary>
public interface ICompressionService
{
    /// <summary>
    /// Compresses a file using gzip.
    /// </summary>
    Task CompressFileAsync(string sourceFile, string destinationFile, CompressionLevel compressionLevel, CancellationToken cancellationToken = default);

    /// <summary>
    /// Decompresses a gzip file.
    /// </summary>
    Task DecompressFileAsync(string sourceFile, string destinationFile, CancellationToken cancellationToken = default);

    /// <summary>
    /// Checks if a file is gzip compressed.
    /// </summary>
    bool IsCompressed(string filePath);
}

/// <summary>
/// Gzip compression service implementation.
/// </summary>
public class GzipCompressionService : ICompressionService
{
    public async Task CompressFileAsync(
        string sourceFile, 
        string destinationFile, 
        CompressionLevel compressionLevel,
        CancellationToken cancellationToken = default)
    {
        await using var sourceStream = File.OpenRead(sourceFile);
        await using var destinationStream = File.Create(destinationFile);
        await using var gzipStream = new GZipStream(destinationStream, compressionLevel);
        
        await sourceStream.CopyToAsync(gzipStream, cancellationToken);
    }

    public async Task DecompressFileAsync(
        string sourceFile, 
        string destinationFile, 
        CancellationToken cancellationToken = default)
    {
        await using var sourceStream = File.OpenRead(sourceFile);
        await using var gzipStream = new GZipStream(sourceStream, CompressionMode.Decompress);
        await using var destinationStream = File.Create(destinationFile);
        
        await gzipStream.CopyToAsync(destinationStream, cancellationToken);
    }

    public bool IsCompressed(string filePath)
    {
        // Check by extension first
        if (filePath.EndsWith(".gz", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        // Check gzip magic bytes (1f 8b)
        if (!File.Exists(filePath)) return false;

        try
        {
            using var stream = File.OpenRead(filePath);
            if (stream.Length < 2) return false;

            var byte1 = stream.ReadByte();
            var byte2 = stream.ReadByte();

            return byte1 == 0x1f && byte2 == 0x8b;
        }
        catch
        {
            return false;
        }
    }
}
