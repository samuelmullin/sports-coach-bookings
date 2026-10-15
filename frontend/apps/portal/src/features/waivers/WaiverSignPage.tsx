import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Download } from 'lucide-react';
import { Button, Card, CardContent } from '@scb/ui';
import { waiverSignaturePdfUrl } from '../../api/endpoints';
import { PageHeader } from '../shared/PageHeader';
import { readReturnTo } from '../shared/return-to';
import { WaiverSigner } from './WaiverSigner';

function WaiverPdfButton({ signatureId }: { signatureId: string }) {
  return (
    <Button asChild variant="outline">
      <a href={waiverSignaturePdfUrl(signatureId)} download>
        <Download className="h-4 w-4" aria-hidden="true" /> Download signed PDF
      </a>
    </Button>
  );
}

export function WaiverSignPage() {
  const { playerId = '', versionId = '' } = useParams<{
    playerId: string;
    versionId: string;
  }>();
  const navigate = useNavigate();
  const returnTo = readReturnTo();
  const [signatureId, setSignatureId] = useState<string | null>(null);
  const [signed, setSigned] = useState(false);

  if (signed) {
    return (
      <div className="flex flex-col gap-4">
        <PageHeader title="Waiver signed" description="A copy is available to download." />
        <Card>
          <CardContent className="flex flex-wrap items-center gap-3 pt-4">
            {signatureId ? <WaiverPdfButton signatureId={signatureId} /> : null}
            {returnTo ? <Button onClick={() => navigate(returnTo)}>Continue booking</Button> : null}
            <Button variant="outline" onClick={() => navigate(`/players/${playerId}`)}>
              Back to player
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to={`/players/${playerId}`}>
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to player
        </Link>
      </Button>
      <PageHeader title="Read and sign" />
      <WaiverSigner
        playerId={playerId}
        versionId={versionId}
        onSigned={(id) => {
          setSignatureId(id);
          setSigned(true);
        }}
      />
    </div>
  );
}
