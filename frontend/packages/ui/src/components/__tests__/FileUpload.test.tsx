import { render, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { FileUpload, type PresignResult } from '../FileUpload';

describe('FileUpload', () => {
  it('requests a presigned URL, uploads, and reports the result', async () => {
    const presign: PresignResult = {
      uploadUrl: 'https://storage.example.com/put/abc',
      fileUrl: 'https://cdn.example.com/abc.pdf',
      key: 'abc.pdf',
    };
    const getPresignedUrl = vi.fn().mockResolvedValue(presign);
    const onUploaded = vi.fn();
    const uploadFile = vi
      .fn()
      .mockImplementation(async (_presign, _file, onProgress: (n: number) => void) => {
        onProgress(100);
      });

    render(
      <FileUpload
        getPresignedUrl={getPresignedUrl}
        onUploaded={onUploaded}
        uploadFile={uploadFile}
        accept="application/pdf"
      />,
    );

    const file = new File(['hello'], 'waiver.pdf', { type: 'application/pdf' });
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    await userEvent.upload(input, file);

    await waitFor(() => expect(onUploaded).toHaveBeenCalledWith(file, presign));
    expect(getPresignedUrl).toHaveBeenCalledWith(file);
    expect(uploadFile).toHaveBeenCalledWith(presign, file, expect.any(Function));
  });

  it('rejects oversized files', async () => {
    const onError = vi.fn();
    render(<FileUpload getPresignedUrl={vi.fn()} onError={onError} maxSizeBytes={1} />);
    const file = new File(['too big'], 'big.pdf', { type: 'application/pdf' });
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    await userEvent.upload(input, file);
    await waitFor(() => expect(onError).toHaveBeenCalled());
  });

  it('reports upload failures', async () => {
    const onError = vi.fn();
    const uploadFile = vi.fn().mockRejectedValue(new Error('network down'));
    render(
      <FileUpload
        getPresignedUrl={vi.fn().mockResolvedValue({
          uploadUrl: 'https://storage.example.com/put/abc',
          fileUrl: 'https://cdn.example.com/abc.pdf',
        })}
        onError={onError}
        uploadFile={uploadFile}
      />,
    );
    const file = new File(['data'], 'x.pdf', { type: 'application/pdf' });
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    await userEvent.upload(input, file);
    await waitFor(() => expect(onError).toHaveBeenCalled());
  });
});
