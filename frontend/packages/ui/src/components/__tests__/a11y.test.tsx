import { render } from '@testing-library/react';
import { describe, it } from 'vitest';
import { expectNoA11yViolations } from '../../test/a11y';
import { Button } from '../Button';
import { FormField } from '../FormField';
import { Input } from '../Input';
import { Modal } from '../Modal';
import { Checkbox } from '../Checkbox';
import { Switch } from '../Switch';

describe('accessibility (axe)', () => {
  it('Button has no violations', async () => {
    const { container } = render(<Button>Save changes</Button>);
    await expectNoA11yViolations(container);
  });

  it('labelled Input has no violations', async () => {
    const { container } = render(
      <FormField label="Email" help="We never share it" id="email">
        <Input type="email" />
      </FormField>,
    );
    await expectNoA11yViolations(container);
  });

  it('Checkbox and Switch with labels have no violations', async () => {
    const { container } = render(
      <div>
        <Checkbox label="Accept terms" defaultChecked />
        <Switch label="Enable reminders" />
      </div>,
    );
    await expectNoA11yViolations(container);
  });

  it('Modal has no violations', async () => {
    const { baseElement } = render(
      <Modal open onOpenChange={() => {}} title="Edit" description="Details">
        <Input aria-label="Name" />
      </Modal>,
    );
    await expectNoA11yViolations(baseElement);
  });
});
