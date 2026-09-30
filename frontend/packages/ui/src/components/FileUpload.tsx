import { UploadCloud } from 'lucide-react';
import { useRef, useState, type DragEvent, type ChangeEvent } from 'react';
import { cn } from '../lib/cn';

export interface PresignResult {
  uploadUrl: string;
  fileUrl: string;
  key?: string;
  headers?: Record<string, string>;
}

export interface FileUploadProgress {
  fileName: string;
  percent: number;
  status: 'uploading' | 'done' | 'error';
  error?: string;
}

export type UploadFunction = (
  presign: PresignResult,
  file: File,
  onProgress: (percent: number) => void,
) => Promise<void>;

export interface FileUploadProps {
  getPresignedUrl: (file: File) => Promise<PresignResult>;
  onUploaded?: (file: File, result: PresignResult) => void;
  onError?: (error: Error, file: File) => void;
  accept?: string;
  multiple?: boolean;
  maxSizeBytes?: number;
  label?: string;
  helperText?: string;
  disabled?: boolean;
  className?: string;
  uploadFile?: UploadFunction;
}

function defaultUpload(
  presign: PresignResult,
  file: File,
  onProgress: (percent: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open('PUT', presign.uploadUrl);
    for (const [key, value] of Object.entries(presign.headers ?? {})) {
      request.setRequestHeader(key, value);
    }
    request.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        onProgress(Math.round((event.loaded / event.total) * 100));
      }
    };
    request.onload = () => {
      if (request.status >= 200 && request.status < 300) resolve();
      else reject(new Error(`Upload failed with status ${request.status}`));
    };
    request.onerror = () => reject(new Error('Upload failed'));
    request.send(file);
  });
}

export function FileUpload({
  getPresignedUrl,
  onUploaded,
  onError,
  accept,
  multiple = false,
  maxSizeBytes,
  label = 'Upload a file',
  helperText,
  disabled,
  className,
  uploadFile = defaultUpload,
}: FileUploadProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [progress, setProgress] = useState<FileUploadProgress[]>([]);

  const updateProgress = (fileName: string, patch: Partial<FileUploadProgress>) => {
    setProgress((current) =>
      current.map((item) => (item.fileName === fileName ? { ...item, ...patch } : item)),
    );
  };

  const handleFiles = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    const selected = Array.from(files);
    setProgress([
      ...selected.map((file) => ({
        fileName: file.name,
        percent: 0,
        status: 'uploading' as const,
      })),
    ]);

    for (const file of selected) {
      if (maxSizeBytes && file.size > maxSizeBytes) {
        updateProgress(file.name, { status: 'error', error: 'File too large' });
        onError?.(new Error('File too large'), file);
        continue;
      }
      try {
        const presign = await getPresignedUrl(file);
        await uploadFile(presign, file, (percent) => updateProgress(file.name, { percent }));
        updateProgress(file.name, { status: 'done', percent: 100 });
        onUploaded?.(file, presign);
      } catch (error) {
        const err = error instanceof Error ? error : new Error('Upload failed');
        updateProgress(file.name, { status: 'error', error: err.message });
        onError?.(err, file);
      }
    }
  };

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragging(false);
    if (disabled) return;
    void handleFiles(event.dataTransfer.files);
  };

  return (
    <div className={cn('flex flex-col gap-2', className)}>
      <div
        role="button"
        tabIndex={disabled ? -1 : 0}
        aria-disabled={disabled}
        aria-label={label}
        onClick={() => !disabled && inputRef.current?.click()}
        onKeyDown={(event) => {
          if ((event.key === 'Enter' || event.key === ' ') && !disabled) {
            event.preventDefault();
            inputRef.current?.click();
          }
        }}
        onDragOver={(event) => {
          event.preventDefault();
          if (!disabled) setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        className={cn(
          'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border p-6 text-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          dragging && 'border-primary bg-muted',
          disabled && 'cursor-not-allowed opacity-50',
        )}
      >
        <UploadCloud className="h-6 w-6 text-muted-foreground" aria-hidden="true" />
        <span className="text-sm font-medium">{label}</span>
        {helperText ? <span className="text-xs text-muted-foreground">{helperText}</span> : null}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept={accept}
        multiple={multiple}
        disabled={disabled}
        className="sr-only"
        onChange={(event: ChangeEvent<HTMLInputElement>) => void handleFiles(event.target.files)}
      />
      {progress.length > 0 ? (
        <ul className="flex flex-col gap-1">
          {progress.map((item) => (
            <li key={item.fileName} className="text-xs">
              <div className="flex items-center justify-between">
                <span className="truncate">{item.fileName}</span>
                <span
                  className={cn(
                    item.status === 'error' && 'text-danger',
                    item.status === 'done' && 'text-green-700',
                  )}
                >
                  {item.status === 'error' ? (item.error ?? 'Failed') : `${item.percent}%`}
                </span>
              </div>
              <progress
                className="h-1 w-full"
                max={100}
                value={item.percent}
                aria-label={`${item.fileName} upload progress`}
              />
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
