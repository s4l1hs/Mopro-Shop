package storage

import (
	"context"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// s3Storage is the S3-compatible impl (Backblaze B2 in prod, MinIO in dev/CI).
// Uses path-style addressing + a custom BaseEndpoint so one code path serves all.
type s3Storage struct {
	client *s3.Client
	bucket string
}

func newS3Storage(ctx context.Context, sc Config) (*s3Storage, error) {
	endpoint := sc.Endpoint
	bucket := sc.Bucket
	region := sc.Region
	if region == "" {
		region = "us-east-1"
	}
	ak, sk := sc.AccessKey, sc.SecretKey
	if bucket == "" || ak == "" || sk == "" {
		return nil, fmt.Errorf("storage(s3): STORAGE_BUCKET/ACCESS_KEY/SECRET_KEY required")
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(region),
		awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(ak, sk, ""),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("storage(s3): load config: %w", err)
	}
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
		o.UsePathStyle = true // B2/MinIO want path-style addressing
	})
	return &s3Storage{client: client, bucket: bucket}, nil
}

func (s *s3Storage) Put(ctx context.Context, key, contentType string, r io.Reader, size int64) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          r,
		ContentType:   aws.String(contentType),
		ContentLength: aws.Int64(size),
	})
	if err != nil {
		return fmt.Errorf("storage(s3): put %s: %w", key, err)
	}
	return nil
}

func (s *s3Storage) Get(ctx context.Context, key string) (io.ReadCloser, string, error) {
	out, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, "", fmt.Errorf("storage(s3): get %s: %w", key, err)
	}
	ct := ""
	if out.ContentType != nil {
		ct = *out.ContentType
	}
	return out.Body, ct, nil
}

func (s *s3Storage) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("storage(s3): delete %s: %w", key, err)
	}
	return nil
}

func (s *s3Storage) PublicURL(key string) string { return publicURL(key) }
