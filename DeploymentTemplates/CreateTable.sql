CREATE TABLE [dbo].[SiteLogTable]
(
	[TimeStamp] DATETIME2 NOT NULL PRIMARY KEY, 
    [SiteStatus] NVARCHAR(50) NULL, 
    [LogRecord] NVARCHAR(MAX) NULL
)