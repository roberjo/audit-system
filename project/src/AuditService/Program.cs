using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using AuditService.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Configure AWS services
builder.Services.AddAWSService<IAmazonDynamoDB>();

// Register application services
builder.Services.AddScoped<IAuditService, AuditService>();

// Configure CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("AllowAll");
app.UseAuthorization();
app.MapControllers();

// Ensure DynamoDB table exists
using (var scope = app.Services.CreateScope())
{
    var dynamoDbClient = scope.ServiceProvider.GetRequiredService<IAmazonDynamoDB>();
    
    try
    {
        var tableResponse = await dynamoDbClient.DescribeTableAsync("AuditEvents");
    }
    catch (ResourceNotFoundException)
    {
        var request = new CreateTableRequest
        {
            TableName = "AuditEvents",
            AttributeDefinitions = new List<AttributeDefinition>
            {
                new AttributeDefinition
                {
                    AttributeName = "Id",
                    AttributeType = ScalarAttributeType.S
                },
                new AttributeDefinition
                {
                    AttributeName = "Timestamp",
                    AttributeType = ScalarAttributeType.S
                }
            },
            KeySchema = new List<KeySchemaElement>
            {
                new KeySchemaElement
                {
                    AttributeName = "Id",
                    KeyType = KeyType.HASH
                },
                new KeySchemaElement
                {
                    AttributeName = "Timestamp",
                    KeyType = KeyType.RANGE
                }
            },
            BillingMode = BillingMode.PAY_PER_REQUEST
        };

        await dynamoDbClient.CreateTableAsync(request);
    }
}

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
