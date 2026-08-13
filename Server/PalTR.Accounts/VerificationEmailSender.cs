using System.Net;
using System.Net.Mail;
using Microsoft.Extensions.Options;

namespace PalTR.Accounts;

public interface IVerificationEmailSender
{
    Task SendAsync(string email, string username, string verificationUrl);
}

public sealed class VerificationEmailSender : IVerificationEmailSender
{
    private readonly SmtpOptions options;
    private readonly IWebHostEnvironment environment;
    private readonly ILogger<VerificationEmailSender> logger;

    public VerificationEmailSender(IOptions<SmtpOptions> options, IWebHostEnvironment environment,
        ILogger<VerificationEmailSender> logger)
    {
        this.options = options.Value;
        this.environment = environment;
        this.logger = logger;
    }

    public async Task SendAsync(string email, string username, string verificationUrl)
    {
        if (!options.IsConfigured)
        {
            if (!environment.IsDevelopment()) throw new InvalidOperationException("SMTP service is not configured.");
            logger.LogWarning("Development verification link for {Email}: {VerificationUrl}", email, verificationUrl);
            return;
        }

        using MailMessage message = new()
        {
            From = new MailAddress(options.FromAddress, options.FromName),
            Subject = "PalTR e-posta doğrulaması",
            Body = $"Merhaba {username},\n\nPalTR hesabını doğrulamak için bağlantıyı aç:\n{verificationUrl}\n\nBu bağlantı sınırlı süre geçerlidir.",
            IsBodyHtml = false
        };
        message.To.Add(email);
        using SmtpClient client = new(options.Host, options.Port)
        {
            EnableSsl = options.UseSsl,
            DeliveryMethod = SmtpDeliveryMethod.Network
        };
        if (!string.IsNullOrWhiteSpace(options.Username))
            client.Credentials = new NetworkCredential(options.Username, options.Password);
        await client.SendMailAsync(message);
    }
}
