import { render, screen } from '@testing-library/react';
import React from 'react';

function Greeting({ name }: { name: string }) {
  return <p>Hello {name}</p>;
}

describe('Greeting component', () => {
  it('renders provided name', () => {
    render(<Greeting name="World" />);
    expect(screen.getByText(/Hello World/i)).toBeInTheDocument();
  });
});
